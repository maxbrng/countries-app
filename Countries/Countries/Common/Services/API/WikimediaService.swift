//
//  WikimediaService.swift
//  Countries
//
//  Created by Max Breuning on 20.01.26.
//

import Foundation
import Combine

// MARK: - Response models

/// Envelope of the Wikimedia Commons `action=query` response.
struct WikiResponse: Codable {

    /// The query payload; absent when the API returned no result set.
    let query: WikiQuery?
}

/// The `query` part of a Commons response.
struct WikiQuery: Codable {

    /// Matched pages, keyed by their internal page id.
    let pages: [String: WikiPage]
}

/// One `File:` page of a Commons search result.
struct WikiPage: Codable {

    /// Page title, usually of the form `File:Something.jpg`.
    let title: String?

    /// Image metadata; the first entry describes the current file version.
    let imageinfo: [WikiImageInfo]?
}

/// Metadata of a single file version on Commons.
struct WikiImageInfo: Codable {

    /// Absolute URL of the original file.
    let url: String

    /// Absolute URL of the scaled thumbnail, when one was requested and produced.
    let thumburl: String?

    /// Description page of the file, kept for attribution purposes.
    let descriptionurl: String?

    /// Pixel width of the original file.
    let width: Int?

    /// Pixel height of the original file.
    let height: Int?
}

// MARK: - Service

/// Resolves one usable photo per key (an ISO2 country code) from Wikimedia Commons
/// and publishes the resulting image URLs.
///
/// Commons returns diagrams, scans, coats of arms and satellite imagery alongside
/// photographs, so every candidate passes a local title and file-type filter before
/// it is accepted.
///
/// - Note: This is the fallback source behind ``UnsplashService``; `PhotoService` owns
///   the fallback policy. Once a URL is published for a key it is never replaced.
@MainActor
final class WikimediaService: ObservableObject {

    // MARK: - Constants

    /// Endpoint, request tuning and the local candidate filters.
    private enum Constants {

        /// Commons API endpoint.
        static let apiEndpoint = "https://commons.wikimedia.org/w/api.php"

        /// Commons namespace 6 holds the `File:` pages.
        static let fileNamespace = "6"

        /// The only status code accepted as a usable response.
        static let okStatusCode = 200

        /// Base delay of the timeout retry; multiplied by the attempt number.
        static let retryBackoffStepNanoseconds = 250_000_000

        /// Search terms appended to the country name, in the order they are tried.
        static let querySuffixes = ["landscape", "landmark", "skyline", "nature"]

        /// Raster formats the cards can display; everything else (svg, pdf, tif,
        /// djvu, ogg, ...) is rejected.
        static let allowedImageFileSuffixes = [".jpg", ".jpeg", ".png", ".webp"]

        /// Flags, maps and heraldry.
        static let blockedSymbolTerms = ["flag", "flags", " map", " maps", "coat of arms",
                                         "coat-of-arms", "emblem", "seal"]

        /// People and portraits.
        static let blockedPeopleTerms = ["portrait", "portraits", "person", "people",
                                         "president", "king", "queen", "prime minister"]

        /// Art and illustration rather than photography.
        static let blockedArtTerms = ["painting", "oil painting", "watercolor", "illustration",
                                      "drawing", "sketch", "artwork", "lithograph", "engraving"]

        /// Satellite and aerial imagery.
        static let blockedAerialTerms = ["satellite", "aerial", "landsat", "sentinel", "nasa",
                                         "esa", "iss", "orthophoto", "google earth"]

        /// Text, scans and documents.
        static let blockedDocumentTerms = ["text", "article", "document", "manual", "brochure",
                                          "leaflet", "newspaper", "scan", "scanned", "page",
                                          "pages", "book", "magazine", "paper", "pdf", "djvu"]

        /// Vectors, icons and logos, which on Commons are mostly SVG.
        static let blockedVectorTerms = ["svg", "icon", "logo", "pictogram"]
    }

    // MARK: - Nested types

    /// How urgently a photo is needed; a higher raw value may cancel a running request.
    enum LoadPriority: Int {

        /// Speculative preloading, runs at `.utility` task priority.
        case background = 0

        /// The user is waiting for this image, runs at `.userInitiated` task priority.
        case userInitiated = 1
    }

    // MARK: - Published state

    /// Resolved image URLs, keyed by the key passed to
    /// ``fetchImageIfNeeded(key:searchTerm:priority:)``.
    @Published private(set) var imageURLs: [String: URL] = [:]

    /// Keys with a request currently in flight.
    @Published private(set) var loadingKeys: Set<String> = []

    /// Human-readable error per key, cleared when a new request for that key starts.
    @Published private(set) var errors: [String: String] = [:]

    // MARK: - Private state

    /// The running request per key, used for de-duplication and cancellation.
    private var tasks: [String: Task<Void, Never>] = [:]

    /// The priority each running request was started with.
    private var taskPriority: [String: LoadPriority] = [:]

    /// URLs already handed out, so two countries never show the same photo.
    private var usedURLStrings = Set<String>()

    /// Requested thumbnail width in pixels.
    private let thumbWidth: Int

    /// Limits how many Commons requests run at the same time.
    private let semaphore: AsyncSemaphore

    // Tuning: the earlier values (50 results, 4s timeout) were too aggressive.

    /// Results requested per query.
    private let perQueryLimit: Int = 25

    /// Timeout of a single request, in seconds.
    private let requestTimeout: TimeInterval = 9

    /// Number of extra attempts after a timeout.
    private let retriesOnTimeout: Int = 1

    /// How many of the query candidates are tried before giving up.
    private let maxCandidates: Int = 2

    // MARK: - Init

    /// Creates the service.
    ///
    /// - Parameters:
    ///   - thumbWidth: Requested thumbnail width in pixels. Defaults to `2000`.
    ///   - maxConcurrent: Number of requests allowed to run in parallel. Defaults to `2`,
    ///     because Commons throttles aggressively.
    init(thumbWidth: Int = 2000, maxConcurrent: Int = 2) {
        self.thumbWidth = thumbWidth
        self.semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    // MARK: - Lookups

    /// - Parameter key: The key a photo was requested for.
    /// - Returns: The resolved image URL, or `nil` while none is known.
    func url(for key: String) -> URL? { imageURLs[key] }

    /// - Parameter key: The key a photo was requested for.
    /// - Returns: `true` while a request for that key is in flight.
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }

    /// - Parameter key: The key a photo was requested for.
    /// - Returns: The last error for that key, or `nil` when there was none.
    func errorMessage(for key: String) -> String? { errors[key] }

    // MARK: - Fetching

    /// Starts resolving one photo for `key`, unless one is already known.
    ///
    /// - Parameters:
    ///   - key: Cache key, in this app an ISO2 country code.
    ///   - searchTerm: Free-text search term; whitespace-only terms are ignored.
    ///   - priority: How urgently the image is needed. Defaults to `.background`.
    /// - Note: A request already running for `key` is only restarted when `priority` is
    ///   higher than the one it was started with. Resolved URLs are never replaced.
    func fetchImageIfNeeded(key: String, searchTerm: String, priority: LoadPriority = .background) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        guard imageURLs[key] == nil else { return }

        if let existing = tasks[key] {
            let current = taskPriority[key] ?? .background
            guard priority.rawValue > current.rawValue else { return }

            existing.cancel()
            tasks[key] = nil
            taskPriority[key] = nil
        }

        loadingKeys.insert(key)
        errors[key] = nil
        taskPriority[key] = priority

        let task = Task(priority: priority == .userInitiated ? .userInitiated : .utility) { [weak self] in
            guard let strong = self else { return }

            // Captured on its own: `strong` in the nested `Task` would undo the weak self.
            let semaphore = strong.semaphore

            await semaphore.wait()
            defer { Task { await semaphore.signal() } }

            do {
                let queries = Array(strong.makeFastCandidates(for: term).prefix(strong.maxCandidates))
                var chosenURL: URL?

                for query in queries {
                    if Task.isCancelled { break }

                    let request = try strong.buildRequest(searchTerm: query,
                                                          limit: strong.perQueryLimit)
                    let decoded = try await strong.fetchWithRetry(request: request,
                                                                 retries: strong.retriesOnTimeout)

                    guard let pages = decoded.query?.pages.values,
                          !pages.isEmpty
                    else {
                        continue
                    }

                    for page in pages {
                        if Task.isCancelled { break }

                        guard let titleRaw = page.title else { continue }
                        let title = titleRaw.lowercased()
                        guard let info = page.imageinfo?.first else { continue }

                        // Hard filters, including "photo file types only".
                        guard !strong.isBlockedTitle(title) else { continue }
                        guard strong.isAllowedImageFile(title: title) else { continue }

                        let urlString = info.thumburl ?? info.url

                        guard !strong.usedURLStrings.contains(urlString) else { continue }
                        guard let candidateURL = URL(string: urlString) else { continue }

                        chosenURL = candidateURL
                        strong.usedURLStrings.insert(urlString)
                        break
                    }

                    if chosenURL != nil { break }
                }

                if let resolvedURL = chosenURL {
                    strong.imageURLs[key] = resolvedURL
                } else {
                    strong.errors[key] = "Wikimedia: kein passendes Foto gefunden."
                }

                strong.loadingKeys.remove(key)
                strong.tasks[key] = nil
                strong.taskPriority[key] = nil

            } catch {
                strong.errors[key] = strong.prettyError(error)
                strong.loadingKeys.remove(key)
                strong.tasks[key] = nil
                strong.taskPriority[key] = nil
            }
        }

        tasks[key] = task
    }

    /// Requests a photo for the first `count` countries, keyed by their ISO2 code.
    ///
    /// - Parameters:
    ///   - countries: Countries to resolve photos for.
    ///   - count: How many of them are preloaded. Defaults to `20`.
    func preload(countries: [Country], count: Int = 20) {
        for country in countries.prefix(count) {
            fetchImageIfNeeded(key: country.iso2, searchTerm: country.nameEnglish, priority: .background)
        }
    }

    /// Cancels every in-flight request and clears the loading state.
    ///
    /// - Note: Already resolved URLs and errors are kept.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        taskPriority.removeAll()
        loadingKeys.removeAll()
    }

    // MARK: - Queries

    /// Builds the search terms for one country, most promising first.
    ///
    /// Instead of a single broad query such as "photo OR ..." the country name is paired
    /// with a scenery term; the local title and file-type filter does the rest.
    ///
    /// - Parameter country: The country name to search for.
    /// - Returns: One query per entry of ``Constants/querySuffixes``.
    private func makeFastCandidates(for country: String) -> [String] {
        Constants.querySuffixes.map { suffix in "\(country) \(suffix)" }
    }

    // MARK: - Filtering

    /// Checks whether a Commons title points at a raster photo the cards can display.
    ///
    /// - Parameter title: Lowercased page title, usually of the form `file:something.jpg`.
    /// - Returns: `true` for the suffixes listed in ``Constants/allowedImageFileSuffixes``.
    private func isAllowedImageFile(title: String) -> Bool {
        Constants.allowedImageFileSuffixes.contains { suffix in title.hasSuffix(suffix) }
    }

    /// Checks whether a title belongs to a category that is never a usable country photo.
    ///
    /// - Parameter title: Lowercased page title.
    /// - Returns: `true` when the title matches one of the blocked term groups.
    private func isBlockedTitle(_ title: String) -> Bool {
        if containsAny(title, Constants.blockedSymbolTerms) { return true }
        if containsAny(title, Constants.blockedPeopleTerms) { return true }
        if containsAny(title, Constants.blockedArtTerms) { return true }
        if containsAny(title, Constants.blockedAerialTerms) { return true }
        if containsAny(title, Constants.blockedDocumentTerms) { return true }
        if containsAny(title, Constants.blockedVectorTerms) { return true }

        return false
    }

    /// - Parameters:
    ///   - text: The string to inspect.
    ///   - terms: Substrings to look for.
    /// - Returns: `true` as soon as `text` contains one of `terms`.
    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: { text.contains($0) })
    }

    // MARK: - Network

    /// Builds the Commons search request for one query.
    ///
    /// - Parameters:
    ///   - searchTerm: The query to send as `gsrsearch`.
    ///   - limit: Maximum number of `File:` pages to return.
    /// - Returns: A `GET` request for the Commons API.
    /// - Throws: `URLError(.badURL)` when the endpoint and query cannot form a URL.
    private func buildRequest(searchTerm: String, limit: Int) throws -> URLRequest {
        var components = URLComponents(string: Constants.apiEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: searchTerm),
            URLQueryItem(name: "gsrnamespace", value: Constants.fileNamespace),
            URLQueryItem(name: "gsrlimit", value: "\(limit)"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|thumbnail|size"),
            URLQueryItem(name: "iiurlwidth", value: "\(thumbWidth)"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("CountriesApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Sends a request and retries it while it times out.
    ///
    /// - Parameters:
    ///   - request: The prepared Commons request.
    ///   - retries: Number of extra attempts after a timeout; other failures are rethrown
    ///     immediately.
    /// - Returns: The decoded ``WikiResponse``.
    /// - Throws: The last transport, status or decoding error.
    /// - Note: The delay between attempts grows linearly with the attempt number.
    private func fetchWithRetry(request: URLRequest, retries: Int) async throws -> WikiResponse {
        var lastError: Error?

        for attempt in 0...retries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == Constants.okStatusCode
                else {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode(WikiResponse.self, from: data)
            } catch {
                lastError = error

                if let urlError = error as? URLError,
                   urlError.code == .timedOut,
                   attempt < retries {
                    let backoff = Constants.retryBackoffStepNanoseconds * (attempt + 1)
                    try? await Task.sleep(nanoseconds: UInt64(backoff))
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    /// Maps an error to the message published in ``errors``.
    ///
    /// - Parameter error: The failure of a search request.
    /// - Returns: A short message for display.
    private func prettyError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Wikimedia: Timeout."
        }
        return error.localizedDescription
    }
}

// MARK: - AsyncSemaphore

/// A counting semaphore for structured concurrency.
///
/// Each ``wait()`` takes one permit and suspends while none is available; ``signal()``
/// returns a permit and resumes the longest-waiting caller first.
///
/// - Note: Callers must return every permit they take, otherwise the slot is lost for
///   the lifetime of the semaphore.
actor AsyncSemaphore {

    /// Permits currently available.
    private var value: Int

    /// Callers suspended in ``wait()``, resumed in FIFO order.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter value: Number of permits, meaning the maximum number of callers that
    ///   may hold the semaphore at the same time.
    init(value: Int) { self.value = value }

    /// Takes one permit, suspending until one is available.
    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Returns one permit, resuming the longest-waiting caller if there is one.
    func signal() {
        if waiters.isEmpty {
            value += 1
            return
        }
        waiters.removeFirst().resume()
    }
}
