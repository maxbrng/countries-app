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

    @Published private(set) var imageURLs: [String: URL] = [:]
    @Published private(set) var loadingKeys: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    private let thumbWidth: Int
    private let semaphore: AsyncSemaphore

    // ✅ Falls du Portrait bevorzugen willst (true) oder egal (false)
    private let preferPortrait: Bool = false

    init(thumbWidth: Int = 2200, maxConcurrent: Int = 6) {
        self.thumbWidth = thumbWidth
        self.semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    func url(for key: String) -> URL? { imageURLs[key] }
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }
    func errorMessage(for key: String) -> String? { errors[key] }

    func fetchImageIfNeeded(key: String, searchTerm: String) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        if imageURLs[key] != nil { return }
        if tasks[key] != nil { return }

        loadingKeys.insert(key)
        errors[key] = nil

        let task = Task { [weak self] in
            guard let self else { return }

            await self.semaphore.wait()
            defer { Task { await self.semaphore.signal() } }

            do {
                let queries = self.makeQueryCandidates(for: term)
                var foundURL: URL?

                for q in queries {
                    if Task.isCancelled { break }

                    let url = try self.buildURL(searchTerm: q, limit: 10)
                    let (data, response) = try await URLSession.shared.data(from: url)

                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continue
                    }

                    let decoded = try JSONDecoder().decode(WikiResponse.self, from: data)
                    guard let pages = decoded.query?.pages.values, !pages.isEmpty else {
                        continue
                    }

                    // ✅ wir iterieren über mehrere Ergebnisse und picken das erste, das “gut” ist
                    if let chosen = self.pickBestPage(from: Array(pages)) {
                        foundURL = chosen
                        break
                    }
                }

                if let u = foundURL {
                    self.imageURLs[key] = u
                }

                self.loadingKeys.remove(key)
                self.tasks[key] = nil

            } catch {
                self.errors[key] = error.localizedDescription
                self.loadingKeys.remove(key)
                self.tasks[key] = nil
            }
        }

        tasks[key] = task
    }

    func preload(countries: [Country]) {
        for c in countries {
            fetchImageIfNeeded(key: c.iso2, searchTerm: c.nameEnglish)
        }
    }

    func cancelAll() {
        for (_, t) in tasks { t.cancel() }
        tasks.removeAll()
        loadingKeys.removeAll()
    }

    // MARK: - Auswahl/Filter

    private func pickBestPage(from pages: [WikiPage]) -> URL? {
        // optional: erst Portrait versuchen, sonst egal
        let candidates = pages.compactMap { page -> (title: String, info: WikiImageInfo)? in
            guard let title = page.title?.lowercased(),
                  let info = page.imageinfo?.first else { return nil }
            return (title: title, info: info)
        }

        // 1) harte Filter: keine flags/maps/wappen/paintings/satellite usw.
        let filtered = candidates.filter { (title, info) in
            !isBlockedTitle(title) && !isSatelliteLike(title) && !isArtworkLike(title)
        }

        if preferPortrait {
            // 2) Portrait bevorzugen, wenn size vorhanden
            if let portrait = filtered.first(where: { (_, info) in
                if let w = info.width, let h = info.height { return h > w }
                return false
            }) {
                return URL(string: portrait.info.thumburl ?? portrait.info.url)
            }
        }

        // 3) sonst: erstes “ok” nehmen
        if let first = filtered.first {
            return URL(string: first.info.thumburl ?? first.info.url)
        }

        return nil
    }

    private func isBlockedTitle(_ t: String) -> Bool {
        // flags
        if t.contains("flag") || t.contains("flags") { return true }

        // maps
        if t.contains("map") || t.contains("maps") { return true }

        // wappen / coat of arms / emblem / seal
        if t.contains("coat of arms") || t.contains("coat-of-arms") { return true }
        if t.contains("emblem") || t.contains("seal") { return true }

        return false
    }

    private func isArtworkLike(_ t: String) -> Bool {
        // Gemälde/Zeichnungen/Illustrationen etc.
        let bad = [
            "painting", "oil on", "oil painting", "watercolor", "gouache",
            "illustration", "drawing", "sketch", "engraving", "lithograph",
            "poster", "artwork", "mural", "fresco", "icon", "stamp"
        ]
        return bad.contains(where: { t.contains($0) })
    }

    private func isSatelliteLike(_ t: String) -> Bool {
        let bad = [
            "satellite", "aerial", "orthophoto", "orthophotograph",
            "landsat", "sentinel", "nasa", "esa", "iss",
            "google earth", "spaceborne"
        ]
        return bad.contains(where: { t.contains($0) })
    }

    // MARK: - Query Kandidaten

    private func makeQueryCandidates(for country: String) -> [String] {
        // ✅ Negative Keywords: keine flags/maps/wappen + keine paintings + keine satellite/aerial
        let negative =
            "-flag -flags -map -maps -\"coat of arms\" -\"coat-of-arms\" -emblem -seal " +
            "-painting -illustration -drawing -sketch -watercolor -poster " +
            "-satellite -aerial -landsat -sentinel -nasa -esa -orthophoto"

        // ✅ Positive Richtung: Foto/Photograph erhöht “echte Fotos”-Treffer
        // (Commons ist nicht perfekt, aber hilft)
        let positive = "photo OR photograph OR \"taken in\" OR \"taken at\""

        return [
            "\(country) landmark \(positive) \(negative)",
            "\(country) landscape \(positive) \(negative)",
            "\(country) skyline \(positive) \(negative)",
            "\(country) city \(positive) \(negative)",
        ]
    }

    // MARK: - URL

    private func buildURL(searchTerm: String, limit: Int) throws -> URL {
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

        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        return url
    }
}



// MARK: - AsyncSemaphore (kleines Hilfsding, damit Parallelität begrenzt ist)

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

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
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }
}
