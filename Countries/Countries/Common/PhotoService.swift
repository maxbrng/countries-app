//
//  PhotoService.swift
//  Countries
//
//  Created by Max Breuning on 21.01.26.
//

//
//  PhotoService.swift
//  Countries
//
//  Unsplash per Bool an/aus + Cooldown per Date (bei 403/429)
//  WICHTIG: Bereits geladene Unsplash-Bilder werden NIEMALS ersetzt.
//           Cooldown bedeutet nur: keine neuen Unsplash-Fetches starten.
//

import Foundation
import Combine

@MainActor
final class PhotoService: ObservableObject {

    // Toggle: Unsplash an/aus
    @Published private(set) var useUnsplash: Bool = true

    @Published private(set) var imageURLs: [String: URL] = [:]
    @Published private(set) var loadingKeys: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let unsplash: UnsplashService
    private let wikimedia: WikimediaService

    private var lastSearchTerm: [String: String] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Cooldown bei 403/429
    private var unsplashDisabledUntil: Date? = nil
    private let unsplashCooldownSeconds: TimeInterval = 60 * 60 // 1h

    init(
        unsplash: UnsplashService,
        wikimedia: WikimediaService
    ) {
        self.unsplash = unsplash
        self.wikimedia = wikimedia

        // Unsplash beobachten
        unsplash.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleUnsplashUpdate()
            }
            .store(in: &cancellables)

        // Wikimedia beobachten
        wikimedia.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sync()
            }
            .store(in: &cancellables)

        sync()
    }

    convenience init() {
        self.init(unsplash: UnsplashService(), wikimedia: WikimediaService())
    }

    // MARK: - Public API

    func setUseUnsplash(_ enabled: Bool) {
        useUnsplash = enabled

        if enabled {
            // Wenn du bewusst wieder Unsplash nutzen willst:
            unsplashDisabledUntil = nil
            // KEIN auto-refresh hier! (sonst wirkt es wie “ersetzen”)
            sync()
        } else {
            // Unsplash aus: stoppe Unsplash-Tasks, aber NICHT “ersetzen”.
            // -> Sync wird künftig Wikimedia bevorzugen, aber wir lassen die bereits
            //    gemergten URLs so, wie sie sind? Nein: UI fragt url(for:) bei uns,
            //    daher: Wenn useUnsplash=false, willst du vermutlich Wikimedia.
            //    Du hast aber explizit gesagt: Unsplash-Bilder sollen nicht ersetzt werden,
            //    wenn sie schon da sind. Also: wir lassen sie bestehen.
            unsplash.cancelAll()
            unsplashDisabledUntil = nil
            // Wichtig: KEIN triggerWikimediaForAllMissing() zwingend, nur für Keys ohne Bild
            triggerWikimediaForAllMissing()
            sync()
        }
    }

    func url(for key: String) -> URL? { imageURLs[key] }
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }
    func errorMessage(for key: String) -> String? { errors[key] }

    func fetchImageIfNeeded(key: String, searchTerm: String) {
        guard !key.isEmpty else { return }
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        lastSearchTerm[key] = term

        // Wenn wir schon IRGENDEIN Bild haben (egal ob Unsplash oder Wikimedia) -> nichts tun.
        // Das garantiert: bereits angezeigtes Unsplash wird nicht “überschrieben”.
        if imageURLs[key] != nil { return }

        // Wenn Unsplash aus -> Wikimedia
        if !useUnsplash {
            wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
            sync()
            return
        }

        // Unsplash an, aber im Cooldown -> Wikimedia (aber nur wenn noch kein Unsplash-Bild existiert)
        if isUnsplashDisabledNow() {
            wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
            sync()
            return
        }

        // Unsplash normal
        unsplash.fetchImageIfNeeded(key: key, searchTerm: term)
        sync()

        // Falls Unsplash failt/0 results -> Wikimedia
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

    // MARK: - Internal

    private func handleUnsplashUpdate() {
        guard useUnsplash else {
            sync()
            return
        }

        // Wenn Unsplash 403/429 etc. -> Cooldown setzen
        if unsplashHasForbiddenOrRateLimit() {
            unsplashDisabledUntil = Date().addingTimeInterval(unsplashCooldownSeconds)
            // Nur fehlende Keys via Wikimedia nachladen
            triggerWikimediaForAllMissing()
        }

        sync()
        triggerFallbackForAll()
    }

    private func isUnsplashDisabledNow() -> Bool {
        guard let until = unsplashDisabledUntil else { return false }
        return Date() < until
    }

    private func unsplashHasForbiddenOrRateLimit() -> Bool {
        return unsplash.errors.values.contains(where: { msg in
            let m = msg.lowercased()
            return m.contains("forbidden")
                || m.contains("rate limit")
                || m.contains("http 403")
                || m.contains("http 429")
        })
    }

    private func sync() {
        
        var merged = wikimedia.imageURLs

        if useUnsplash {
            for (k, u) in unsplash.imageURLs {
                merged[k] = u
            }
        }

        imageURLs = merged

        // Loading: wenn Unsplash disabled, zeigen wir nur Wikimedia loading an
        if useUnsplash && !isUnsplashDisabledNow() {
            loadingKeys = unsplash.loadingKeys.union(wikimedia.loadingKeys)
        } else {
            loadingKeys = wikimedia.loadingKeys
        }

        // Errors: wenn Bild existiert -> Error ausblenden
        var mergedErrors: [String: String] = [:]

        if useUnsplash && !isUnsplashDisabledNow() {
            for (k, e) in unsplash.errors { mergedErrors[k] = e }
        }
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
        // Wenn schon Bild da -> done
        if imageURLs[key] != nil { return }

        // Unsplash aus oder disabled -> Wikimedia
        if !useUnsplash || isUnsplashDisabledNow() {
            guard let term = lastSearchTerm[key] else { return }
            wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
            return
        }

        // Unsplash Error für Key -> Wikimedia
        if unsplash.errors[key] != nil {
            guard let term = lastSearchTerm[key] else { return }
            wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
            return
        }

        // Unsplash lädt noch -> warten
        if unsplash.loadingKeys.contains(key) { return }

        // Unsplash hat Bild -> kein fallback
        if unsplash.imageURLs[key] != nil { return }

        // Unsplash fertig, aber kein Bild -> Wikimedia
        guard let term = lastSearchTerm[key] else { return }
        wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
    }

    private func triggerWikimediaForAllMissing() {
        for (key, term) in lastSearchTerm {
            // Nur wenn wir wirklich noch KEIN Bild haben
            if imageURLs[key] == nil {
                wikimedia.fetchImageIfNeeded(key: key, searchTerm: term)
            }
        }
    }
}
