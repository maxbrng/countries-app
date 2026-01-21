//
//  PhotoService.swift
//  Countries
//
//  Created by Max Breuning on 21.01.26.
//


import Foundation
import Combine

@MainActor
final class PhotoService: ObservableObject {

    @Published private(set) var imageURLs: [String: URL] = [:]
    @Published private(set) var loadingKeys: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let unsplash: UnsplashService
    private let wikimedia: WikimediaService

    // pro key merken wir uns den Suchterm, damit Fallback weiß, wonach es suchen soll
    private var lastSearchTerm: [String: String] = [:]

    private var cancellables = Set<AnyCancellable>()

    init(
        unsplash: UnsplashService,
        wikimedia: WikimediaService
    ) {
        self.unsplash = unsplash
        self.wikimedia = wikimedia

        // ✅ Combine-observer statt AsyncSequence (verhindert "demand" crash)
        unsplash.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sync()
                self.triggerFallbackForAll()
            }
            .store(in: &cancellables)

        wikimedia.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sync()
            }
            .store(in: &cancellables)

        sync()
    }

    convenience init() {
         self.init(unsplash: UnsplashService(), wikimedia: WikimediaService())
     }
    // MARK: - UI API

    func url(for key: String) -> URL? {
        imageURLs[key]
    }

    func isLoading(_ key: String) -> Bool {
        loadingKeys.contains(key)
    }

    func errorMessage(for key: String) -> String? {
        errors[key]
    }

    func fetchImageIfNeeded(key: String, searchTerm: String) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        lastSearchTerm[key] = term

        // schon da -> nichts
        if imageURLs[key] != nil { return }

        // 1) Unsplash versuchen
        unsplash.fetchImageIfNeeded(key: key, searchTerm: term)

        // sofort state aktualisieren
        sync()

        // falls Unsplash sofort schon “fertig ohne Ergebnis” ist, Fallback starten
        triggerFallbackIfNeeded(for: key)
    }

    func preload(countries: [Country]) {
        for c in countries {
            fetchImageIfNeeded(key: c.iso2, searchTerm: c.nameEnglish)
        }
    }

    func cancelAll() {
        unsplash.cancelAll()
        wikimedia.cancelAll()
        sync()
    }

    // MARK: - Sync

    private func sync() {
        // Priorität: Unsplash > Wikimedia
        var merged = wikimedia.imageURLs
        for (k, u) in unsplash.imageURLs {
            merged[k] = u
        }
        imageURLs = merged

        loadingKeys = unsplash.loadingKeys.union(wikimedia.loadingKeys)

        // Errors sammeln, aber wenn Bild existiert -> Fehler ausblenden
        var mergedErrors: [String: String] = [:]
        for (k, e) in unsplash.errors { mergedErrors[k] = e }
        for (k, e) in wikimedia.errors { mergedErrors[k] = e }

        for k in imageURLs.keys {
            mergedErrors[k] = nil
        }
        errors = mergedErrors.compactMapValues { $0 }
    }

    // MARK: - Fallback

    private func triggerFallbackForAll() {
        for key in lastSearchTerm.keys {
            triggerFallbackIfNeeded(for: key)
        }
    }

    private func triggerFallbackIfNeeded(for key: String) {
        // wenn wir schon ein Bild haben -> fertig
        if imageURLs[key] != nil { return }

        // Unsplash lädt noch -> warten
        if unsplash.loadingKeys.contains(key) { return }

        // Unsplash hat eins -> kein Fallback
        if unsplash.imageURLs[key] != nil { return }

        // Unsplash ist fertig und hat keins geliefert -> Wikimedia starten
        guard let term = lastSearchTerm[key] else { return }
        wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
    }
}
