//
//  UnsplashService.swift
//  Countries
//
//  Created by Max Breuning on 21.01.26.
//


import Foundation
import Combine

struct UnsplashSearchResponse: Codable {
    let total: Int
    let total_pages: Int
    let results: [UnsplashPhoto]
}

struct UnsplashPhoto: Codable {
    let id: String
    let width: Int
    let height: Int
    let urls: UnsplashPhotoURLs
}

struct UnsplashPhotoURLs: Codable {
    let raw: String
    let full: String
    let regular: String
    let small: String
    let thumb: String
}

import Foundation

@MainActor
final class UnsplashService: ObservableObject {

    @Published private(set) var imageURLs: [String: URL] = [:]
    @Published private(set) var loadingKeys: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    private let semaphore: AsyncSemaphore
    private let accessKey: String

    enum Variant { case regular, small, thumb }
    private let preferredVariant: Variant = .regular

    init(accessKey: String? = nil, maxConcurrent: Int = 6) {
        self.semaphore = AsyncSemaphore(value: maxConcurrent)

        if let key = accessKey, !key.isEmpty {
            self.accessKey = key
        } else if let keyFromPlist = Bundle.main.object(forInfoDictionaryKey: "UNSPLASH_ACCESS_KEY") as? String,
                  !keyFromPlist.isEmpty {
            self.accessKey = keyFromPlist
        } else {
            self.accessKey = ""
            print("⚠️ UnsplashService: Missing UNSPLASH_ACCESS_KEY. Add it to Info.plist or pass it into init(accessKey:).")
        }
    }

    func url(for key: String) -> URL? { imageURLs[key] }
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }
    func errorMessage(for key: String) -> String? { errors[key] }

    func fetchImageIfNeeded(key: String, searchTerm: String) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        guard !accessKey.isEmpty else {
            errors[key] = "Unsplash Access Key fehlt (UNSPLASH_ACCESS_KEY)."
            return
        }

        if imageURLs[key] != nil { return }
        if tasks[key] != nil { return }

        loadingKeys.insert(key)
        errors[key] = nil

        let task = Task { [weak self] in
            guard let self else { return }

            await self.semaphore.wait()
            defer { Task { await self.semaphore.signal() } }

            do {
                let request = try self.buildRequest(searchTerm: term)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(http.statusCode) else {
                    throw UnsplashHTTPError(statusCode: http.statusCode)
                }

                let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)

                guard let first = decoded.results.first else {
                    // kein Ergebnis -> kein Error, nur fertig
                    self.loadingKeys.remove(key)
                    self.tasks[key] = nil
                    return
                }

                // ✅ Policy-friendly: Download tracking (hilft gegen 403/Policy-Probleme)
                Task.detached { [accessKey] in
                    await Self.trackDownload(photoID: first.id, accessKey: accessKey)
                }

                let urlString: String
                switch self.preferredVariant {
                case .regular: urlString = first.urls.regular
                case .small:   urlString = first.urls.small
                case .thumb:   urlString = first.urls.thumb
                }

                if let imageURL = URL(string: urlString) {
                    self.imageURLs[key] = imageURL
                }

                self.loadingKeys.remove(key)
                self.tasks[key] = nil

            } catch {
                self.errors[key] = self.prettyError(error)
                self.loadingKeys.remove(key)
                self.tasks[key] = nil

                if let urlError = error as? URLError {
                    print("Unsplash URLError:", urlError.code.rawValue, urlError.code)
                } else {
                    print("Unsplash error:", error)
                }
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

    private func buildRequest(searchTerm: String) throws -> URLRequest {
        var components = URLComponents(string: "https://api.unsplash.com/search/photos")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "\(searchTerm) landscape"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "content_filter", value: "high")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CountriesApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func prettyError(_ error: Error) -> String {
        if let httpErr = error as? UnsplashHTTPError {
            switch httpErr.statusCode {
            case 401: return "Unsplash: Unauthorized (Access Key falsch?)."
            case 403: return "Unsplash: Forbidden (Rate Limit / Policy)."
            case 429: return "Unsplash: Rate Limit erreicht."
            default:  return "Unsplash: HTTP \(httpErr.statusCode)"
            }
        }
        return error.localizedDescription
    }

    private static func trackDownload(photoID: String, accessKey: String) async {
        guard let url = URL(string: "https://api.unsplash.com/photos/\(photoID)/download") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CountriesApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: request)
    }
}

struct UnsplashHTTPError: Error {
    let statusCode: Int
}
