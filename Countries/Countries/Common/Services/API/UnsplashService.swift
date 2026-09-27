//
//  UnsplashService.swift
//  Countries
//
//  Created by Max Breuning on 21.01.26.
//

import Foundation
import Combine
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries", category: "Unsplash")

// MARK: - Response models

/// One page of the Unsplash `search/photos` response.
struct UnsplashSearchResponse: Codable {

    /// Total number of photos matching the query.
    let total: Int

    /// Number of pages the API would serve for the current page size.
    let total_pages: Int

    /// The photos of the requested page, at most `per_page` entries.
    let results: [UnsplashPhoto]
}

/// A single photo of an Unsplash search result.
struct UnsplashPhoto: Codable {

    /// Unsplash identifier, needed for the download-tracking call.
    let id: String

    /// Pixel width of the original photo.
    let width: Int

    /// Pixel height of the original photo.
    let height: Int

    /// The pre-rendered size variants Unsplash offers for this photo.
    let urls: UnsplashPhotoURLs
}

/// The size variants Unsplash returns per photo, as absolute URL strings.
struct UnsplashPhotoURLs: Codable {

    /// Unscaled original, far larger than anything the app displays.
    let raw: String

    /// Full resolution, re-encoded by Unsplash.
    let full: String

    /// Mid-size variant, the one the app requests by default.
    let regular: String

    /// Small variant.
    let small: String

    /// Thumbnail variant.
    let thumb: String
}

// MARK: - Service

/// Resolves one landscape photo per key (an ISO2 country code) from the Unsplash
/// search API and publishes the resulting image URLs.
///
/// - Note: This is the primary photo source; ``WikimediaService`` is the fallback.
///   Both are fronted by `PhotoService`, which owns the fallback and cooldown policy.
///   Once a URL is published for a key it is never replaced.
@MainActor
final class UnsplashService: ObservableObject {

    // MARK: - Constants

    /// Endpoints, request tuning and the status codes this service reacts to.
    private enum Constants {

        /// HTTP status codes treated as a successful response.
        static let successStatusCodes = 200...299

        /// Access key was rejected.
        static let unauthorized = 401

        /// Request was refused, in practice rate limiting or a policy violation.
        static let forbidden = 403

        /// Client exceeded its request quota.
        static let tooManyRequests = 429

        /// Photo search endpoint.
        static let searchEndpoint = "https://api.unsplash.com/search/photos"

        /// Base endpoint of a single photo; the download-tracking path is appended to it.
        static let photosEndpoint = "https://api.unsplash.com/photos"

        /// Only the first page is requested: a single hit is enough for one card.
        static let requestedPage = 1

        /// One result per request keeps the response small and the quota use low.
        static let resultsPerPage = 1

        /// Requested photo orientation, matching the wide country cards.
        static let orientation = "landscape"

        /// Unsplash content filter level.
        static let contentFilter = "high"

        /// Appended to the search term to bias results towards scenery.
        static let searchTermSuffix = "landscape"

        /// Authorization scheme Unsplash expects in front of the access key.
        static let authorizationScheme = "Client-ID"

        /// `User-Agent` this app identifies itself with.
        static let userAgent = "CountriesApp/1.0 (iOS)"

        /// `Info.plist` key that carries the Unsplash access key.
        static let accessKeyInfoPlistKey = "UNSPLASH_ACCESS_KEY"
    }

    // MARK: - Nested types

    /// The Unsplash size variant a resolved URL points at.
    enum Variant {

        /// Mid-size variant, large enough for full-width cards.
        case regular

        /// Small variant.
        case small

        /// Thumbnail variant.
        case thumb
    }

    // MARK: - Published state

    /// Resolved image URLs, keyed by the key passed to ``fetchImageIfNeeded(key:searchTerm:)``.
    @Published private(set) var imageURLs: [String: URL] = [:]

    /// Keys with a request currently in flight.
    @Published private(set) var loadingKeys: Set<String> = []

    /// Human-readable error per key, cleared when a new request for that key starts.
    @Published private(set) var errors: [String: String] = [:]

    // MARK: - Private state

    /// The running request per key, used for de-duplication and cancellation.
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Limits how many Unsplash requests run at the same time.
    private let semaphore: AsyncSemaphore

    /// Unsplash access key; empty when none was configured.
    private let accessKey: String

    /// The variant resolved URLs point at.
    private let preferredVariant: Variant = .regular

    // MARK: - Init

    /// Creates the service and resolves the access key.
    ///
    /// - Parameters:
    ///   - accessKey: Access key to use. Defaults to `nil`, which reads
    ///     `UNSPLASH_ACCESS_KEY` from the app's `Info.plist`.
    ///   - maxConcurrent: Number of requests allowed to run in parallel. Defaults to `6`.
    /// - Note: When no key can be resolved the service stays usable but every fetch
    ///   fails fast with an error for the requested key.
    init(accessKey: String? = nil, maxConcurrent: Int = 6) {
        self.semaphore = AsyncSemaphore(value: maxConcurrent)

        if let key = accessKey, !key.isEmpty {
            self.accessKey = key
        } else if let plistKey = Bundle.main.object(forInfoDictionaryKey: Constants.accessKeyInfoPlistKey) as? String,
                  !plistKey.isEmpty {
            self.accessKey = plistKey
        } else {
            self.accessKey = ""
            logger.warning("Missing UNSPLASH_ACCESS_KEY. Add it to Info.plist or pass it into init(accessKey:).")
        }
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

    /// Starts resolving one photo for `key`, unless one is already known or in flight.
    ///
    /// - Parameters:
    ///   - key: Cache key, in this app an ISO2 country code.
    ///   - searchTerm: Free-text search term; whitespace-only terms are ignored.
    /// - Note: A resolved URL is never replaced, so calling this repeatedly is cheap.
    func fetchImageIfNeeded(key: String, searchTerm: String) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        guard !accessKey.isEmpty else {
            errors[key] = "Unsplash Access Key fehlt (UNSPLASH_ACCESS_KEY)."
            return
        }

        guard imageURLs[key] == nil else { return }
        guard tasks[key] == nil else { return }

        loadingKeys.insert(key)
        errors[key] = nil

        let task = Task { [weak self] in
            guard let strong = self else { return }

            // Captured on its own: `strong` in the nested `Task` would undo the weak self.
            let semaphore = strong.semaphore

            await semaphore.wait()
            defer { Task { await semaphore.signal() } }

            do {
                let request = try strong.buildRequest(searchTerm: term)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard Constants.successStatusCodes.contains(http.statusCode) else {
                    throw UnsplashHTTPError(statusCode: http.statusCode)
                }

                let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)

                guard let first = decoded.results.first else {
                    // No result is not an error, the key is simply done.
                    strong.loadingKeys.remove(key)
                    strong.tasks[key] = nil
                    return
                }

                // Policy-friendly download tracking, which helps against 403 / policy problems.
                Task.detached { [accessKey = strong.accessKey] in
                    await Self.trackDownload(photoID: first.id, accessKey: accessKey)
                }

                if let imageURL = URL(string: strong.imageURLString(from: first.urls)) {
                    strong.imageURLs[key] = imageURL
                }

                strong.loadingKeys.remove(key)
                strong.tasks[key] = nil

            } catch {
                strong.errors[key] = strong.prettyError(error)
                strong.loadingKeys.remove(key)
                strong.tasks[key] = nil

                let description = (error as NSError).localizedDescription
                logger.error("Unsplash request failed: \(description, privacy: .public)")
            }
        }

        tasks[key] = task
    }

    /// Requests a photo for every country, keyed by its ISO2 code.
    ///
    /// - Parameter countries: Countries to resolve photos for.
    func preload(countries: [Country]) {
        for country in countries {
            fetchImageIfNeeded(key: country.iso2, searchTerm: country.nameEnglish)
        }
    }

    /// Cancels every in-flight request and clears the loading state.
    ///
    /// - Note: Already resolved URLs and errors are kept.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        loadingKeys.removeAll()
    }

    // MARK: - Request building

    /// Builds the authorized search request for one term.
    ///
    /// - Parameter searchTerm: The already trimmed search term.
    /// - Returns: A `GET` request carrying the access key in its `Authorization` header.
    /// - Throws: `URLError(.badURL)` when the endpoint and query cannot form a URL.
    private func buildRequest(searchTerm: String) throws -> URLRequest {
        var components = URLComponents(string: Constants.searchEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "query", value: "\(searchTerm) \(Constants.searchTermSuffix)"),
            URLQueryItem(name: "page", value: "\(Constants.requestedPage)"),
            URLQueryItem(name: "per_page", value: "\(Constants.resultsPerPage)"),
            URLQueryItem(name: "orientation", value: Constants.orientation),
            URLQueryItem(name: "content_filter", value: Constants.contentFilter)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("\(Constants.authorizationScheme) \(accessKey)",
                         forHTTPHeaderField: "Authorization")
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Picks the URL string of ``preferredVariant`` from a photo's variants.
    ///
    /// - Parameter urls: The variants Unsplash returned for one photo.
    /// - Returns: The absolute URL string of the preferred variant.
    private func imageURLString(from urls: UnsplashPhotoURLs) -> String {
        switch preferredVariant {
        case .regular: return urls.regular
        case .small: return urls.small
        case .thumb: return urls.thumb
        }
    }

    // MARK: - Error mapping

    /// Maps an error to the message published in ``errors``.
    ///
    /// - Parameter error: The failure of a search request.
    /// - Returns: A short message for display.
    /// - Note: `PhotoService` detects the Unsplash cooldown case by matching on these
    ///   messages, so their wording is load-bearing. Keep "Forbidden" and "Rate Limit"
    ///   in the 403 and 429 texts.
    private func prettyError(_ error: Error) -> String {
        if let httpErr = error as? UnsplashHTTPError {
            switch httpErr.statusCode {
            case Constants.unauthorized: return "Unsplash: Unauthorized (Access Key falsch?)."
            case Constants.forbidden: return "Unsplash: Forbidden (Rate Limit / Policy)."
            case Constants.tooManyRequests: return "Unsplash: Rate Limit erreicht."
            default: return "Unsplash: HTTP \(httpErr.statusCode)"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Download tracking

    /// Notifies Unsplash that a photo was used, as their API guidelines require.
    ///
    /// - Parameters:
    ///   - photoID: Identifier of the used photo; an empty id is ignored.
    ///   - accessKey: Access key for the `Authorization` header.
    /// - Note: Fire and forget, the result is intentionally discarded.
    private static func trackDownload(photoID: String, accessKey: String) async {
        guard !photoID.isEmpty else { return }
        guard let url = URL(string: "\(Constants.photosEndpoint)/\(photoID)/download") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("\(Constants.authorizationScheme) \(accessKey)",
                         forHTTPHeaderField: "Authorization")
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Errors

/// A non-success HTTP status returned by the Unsplash API.
struct UnsplashHTTPError: Error {

    /// The status code of the rejected response.
    let statusCode: Int
}
