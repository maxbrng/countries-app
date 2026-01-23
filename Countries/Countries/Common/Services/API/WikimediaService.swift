//
//  WikimediaService.swift
//  Countries
//
//  Created by Max Breuning on 20.01.26.
//

import Foundation
import Combine

struct WikiResponse: Codable {
    let query: WikiQuery?
}

struct WikiQuery: Codable {
    let pages: [String: WikiPage]
}

struct WikiPage: Codable {
    let title: String?
    let imageinfo: [WikiImageInfo]?
}

struct WikiImageInfo: Codable {
    let url: String
    let thumburl: String?
    let descriptionurl: String?
    let width: Int?
    let height: Int?
}

@MainActor
final class WikimediaService: ObservableObject {

    enum LoadPriority: Int {
        case background = 0
        case userInitiated = 1
    }

    @Published private(set) var imageURLs: [String: URL] = [:]
    @Published private(set) var loadingKeys: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    private var taskPriority: [String: LoadPriority] = [:]

    private var usedURLStrings = Set<String>()

    private let thumbWidth: Int
    private let semaphore: AsyncSemaphore

    // ✅ Tuning (50 + 4s ist “zu hart”)
    private let perQueryLimit: Int = 25
    private let requestTimeout: TimeInterval = 9
    private let retriesOnTimeout: Int = 1
    private let maxCandidates: Int = 2

    init(thumbWidth: Int = 2000, maxConcurrent: Int = 2) {
        self.thumbWidth = thumbWidth
        self.semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    func url(for key: String) -> URL? { imageURLs[key] }
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }
    func errorMessage(for key: String) -> String? { errors[key] }

    func fetchImageIfNeeded(key: String, searchTerm: String, priority: LoadPriority = .background) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        if imageURLs[key] != nil { return }

        if let existing = tasks[key] {
            let current = taskPriority[key] ?? .background
            if priority.rawValue > current.rawValue {
                existing.cancel()
                tasks[key] = nil
                taskPriority[key] = nil
            } else {
                return
            }
        }

        loadingKeys.insert(key)
        errors[key] = nil
        taskPriority[key] = priority

        let task = Task(priority: priority == .userInitiated ? .userInitiated : .utility) { [weak self] in
            guard let self else { return }

            await semaphore.wait()
            defer { Task { await self.semaphore.signal() } }

            do {
                let queries = Array(makeFastCandidates(for: term).prefix(maxCandidates))
                var chosenURL: URL? = nil

                for q in queries {
                    if Task.isCancelled { break }

                    let request = try buildRequest(searchTerm: q, limit: perQueryLimit)
                    let decoded = try await fetchWithRetry(request: request, retries: retriesOnTimeout)

                    guard let pages = decoded.query?.pages.values, !pages.isEmpty else {
                        continue
                    }

                    for page in pages {
                        if Task.isCancelled { break }

                        guard let titleRaw = page.title else { continue }
                        let title = titleRaw.lowercased()
                        guard let info = page.imageinfo?.first else { continue }

                        // ✅ harte Filter inkl. “nur Foto-Dateitypen”
                        if isBlockedTitle(title) { continue }
                        if !isAllowedImageFile(title: title) { continue }

                        let urlString = info.thumburl ?? info.url

                        if usedURLStrings.contains(urlString) { continue }
                        guard let u = URL(string: urlString) else { continue }

                        chosenURL = u
                        usedURLStrings.insert(urlString)
                        break
                    }

                    if chosenURL != nil { break }
                }

                if let u = chosenURL {
                    imageURLs[key] = u
                } else {
                    errors[key] = "Wikimedia: kein passendes Foto gefunden."
                }

                loadingKeys.remove(key)
                tasks[key] = nil
                taskPriority[key] = nil

            } catch {
                errors[key] = prettyError(error)
                loadingKeys.remove(key)
                tasks[key] = nil
                taskPriority[key] = nil
            }
        }

        tasks[key] = task
    }

    func preload(countries: [Country], count: Int = 20) {
        for c in countries.prefix(count) {
            fetchImageIfNeeded(key: c.iso2, searchTerm: c.nameEnglish, priority: .background)
        }
    }

    func cancelAll() {
        for (_, t) in tasks { t.cancel() }
        tasks.removeAll()
        taskPriority.removeAll()
        loadingKeys.removeAll()
    }

    // MARK: - Queries (einfach halten)

    private func makeFastCandidates(for country: String) -> [String] {
        // ✅ Wir versuchen statt “photo OR …” einfach: Landschaft/Sehenswürdigkeit.
        // Den Rest macht unser lokaler Filter + filetype.
        return [
            "\(country) landscape",
            "\(country) landmark",
            "\(country) skyline",
            "\(country) nature"
        ]
    }

    // MARK: - Filtering

    /// ✅ nur echte Rasterbilder für deine Cards:
    /// jpg/jpeg/png/webp (kein svg, pdf, tif, djvu, ogg, etc.)
    private func isAllowedImageFile(title: String) -> Bool {
        // Commons Titles sind meist wie: "File:Something.jpg"
        // Wir checken auf Endung:
        if title.hasSuffix(".jpg") || title.hasSuffix(".jpeg") || title.hasSuffix(".png") || title.hasSuffix(".webp") {
            return true
        }
        return false
    }

    private func isBlockedTitle(_ t: String) -> Bool {
        // flags / maps / wappen
        if containsAny(t, ["flag", "flags", " map", " maps", "coat of arms", "coat-of-arms", "emblem", "seal"]) { return true }

        // people / portraits
        if containsAny(t, ["portrait", "portraits", "person", "people", "president", "king", "queen", "prime minister"]) { return true }

        // art / illustration
        if containsAny(t, ["painting", "oil painting", "watercolor", "illustration", "drawing", "sketch", "artwork", "lithograph", "engraving"]) { return true }

        // satellite / aerial
        if containsAny(t, ["satellite", "aerial", "landsat", "sentinel", "nasa", "esa", "iss", "orthophoto", "google earth"]) { return true }
        
        // ✅ Text/Scans/Documents
        if containsAny(t, [
            "text", "article", "document", "manual", "brochure", "leaflet", "newspaper",
            "scan", "scanned", "page", "pages", "book", "magazine", "paper", "pdf", "djvu"
        ]) { return true }

        // ✅ Vektoren/Icons/Logos (meist SVG)
        if containsAny(t, ["svg", "icon", "logo", "pictogram"]) { return true }

        return false
    }

    private func containsAny(_ t: String, _ list: [String]) -> Bool {
        list.contains(where: { t.contains($0) })
    }

    // MARK: - Network

    private func buildRequest(searchTerm: String, limit: Int) throws -> URLRequest {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: searchTerm),
            URLQueryItem(name: "gsrnamespace", value: "6"),
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

    private func fetchWithRetry(request: URLRequest, retries: Int) async throws -> WikiResponse {
        var lastError: Error?

        for attempt in 0...retries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode(WikiResponse.self, from: data)
            } catch {
                lastError = error

                if let e = error as? URLError, e.code == .timedOut, attempt < retries {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private func prettyError(_ error: Error) -> String {
        if let e = error as? URLError, e.code == .timedOut {
            return "Wikimedia: Timeout."
        }
        return error.localizedDescription
    }
}


// MARK: - AsyncSemaphore

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
