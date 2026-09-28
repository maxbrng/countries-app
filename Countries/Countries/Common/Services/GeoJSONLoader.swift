//
//  GeoJSONLoader.swift
//  Countries
//
//  Swift 6 / Concurrency-safe implementation:
//  - Bundle IO + JSON decoding happen off-main
//  - Decoded FeatureCollections are cached in an actor
//  - ISO resolution uses a Sendable `ResolverIndex` (no SwiftData models across actors)
//  - Convenience overload for `CountryIndex` is @MainActor (CountryIndex contains SwiftData models)
//

import Foundation
import UIKit

/// Shared loader that decodes GeoJSON from the app bundle and resolves each feature to an ISO2 code.
/// The resulting `ResolvedFeature` can be used by different renderers (Flat / Globe) without duplicating decoding code.
nonisolated enum GeoJSONLoader {

    // MARK: - Resolver

    /// Sendable lookup tables (no SwiftData types) for resolving features to ISO2.
    struct ResolverIndex: Sendable {
        let iso3ToIso2: [String: String]
        let nameToIso2: [String: String]

        init(iso3ToIso2: [String: String], nameToIso2: [String: String]) {
            self.iso3ToIso2 = iso3ToIso2
            self.nameToIso2 = nameToIso2
        }
    }

    // MARK: - Output

    struct ResolvedFeature: Sendable {
        let iso2: String
        let geometry: GeoJSON.Geometry
        let properties: [String: JSONValue]
    }

    // MARK: - Key config

    nonisolated struct KeySet: Sendable {
        let isoKeys: [String]
        let nameKeys: [String]

        init(
            isoKeys: [String] = ["ISO_A2", "iso_a2", "ISO2", "POSTAL", "ISO_A3", "iso_a3", "ADM0_A3"],
            nameKeys: [String] = ["admin", "name", "ADMIN", "NAME", "name_en", "NAME_EN"]
        ) {
            self.isoKeys = isoKeys
            self.nameKeys = nameKeys
        }
    }

    // MARK: - API

    /// Primary API: resolves using a Sendable resolver.
    static func loadResolvedFeatures(
        resource: String = "countries",
        resolver: ResolverIndex,
        keySet: KeySet = .init()
    ) async throws -> [ResolvedFeature] {

        let collection = try await GeoJSONResourceCache.shared.featureCollection(resource: resource)

        // Resolve off-main (pure data work).
        return await Task.detached(priority: .userInitiated) {
            var resolved: [ResolvedFeature] = []
            resolved.reserveCapacity(collection.features.count)

            for feature in collection.features {
                let props = feature.properties ?? [:]

                let rawISO = props.firstString(for: keySet.isoKeys)?.lowercased()
                let rawName = props.firstString(for: keySet.nameKeys)?.lowercased()

                let iso2 = resolveISO2(rawISO: rawISO, rawName: rawName, resolver: resolver)
                guard let iso2, iso2.count == 2 else { continue }

                resolved.append(.init(iso2: iso2, geometry: feature.geometry, properties: props))
            }

            return resolved
        }.value
    }

    /// Convenience overload used by existing code (Globe/Flat VMs).
    /// `CountryIndex` contains SwiftData models, so keep this on the MainActor.
    @MainActor
    static func loadResolvedFeatures(
        resource: String = "countries",
        index: CountryIndex,
        keySet: KeySet = .init()
    ) async throws -> [ResolvedFeature] {
        try await loadResolvedFeatures(resource: resource, resolver: index.resolverIndex, keySet: keySet)
    }

    // MARK: - Private

    /// Resolves one feature to a seeded country.
    ///
    /// - Parameters:
    ///   - rawISO: Lowercased value of the first ISO key the feature carries, if any.
    ///   - rawName: Lowercased value of the first name key the feature carries, if any.
    ///   - resolver: The lookup tables built from the seeded countries.
    /// - Returns: The lowercased ISO2 code, or `nil` when the feature has no counterpart
    ///   among the seeded countries.
    /// - Note: A code of an unexpected length falls through to the name, it does not end the
    ///   attempt. Natural Earth carries `iso_a2 = "CN-TW"` for Taiwan, and returning `nil` on
    ///   that meant Taiwan was silently absent from the map. Five of 242 features stay
    ///   unresolved after this, all of them correctly: Northern Cyprus, Siachen Glacier,
    ///   Indian Ocean Territories, Somaliland and Ashmore and Cartier Islands are not seeded.
    private static func resolveISO2(rawISO: String?, rawName: String?, resolver: ResolverIndex) -> String? {

        guard let rawISO, rawISO != "-99" else {
            return nameLookup(rawName: rawName, resolver: resolver)
        }

        switch rawISO.count {
        case 2:
            return rawISO
        case 3:
            return resolver.iso3ToIso2[rawISO] ?? nameLookup(rawName: rawName, resolver: resolver)
        default:
            return nameLookup(rawName: rawName, resolver: resolver)
        }
    }

    /// Looks a feature up by its name, the last resort of ``resolveISO2(rawISO:rawName:resolver:)``.
    ///
    /// - Parameters:
    ///   - rawName: Lowercased value of the first name key the feature carries, if any.
    ///   - resolver: The lookup tables built from the seeded countries.
    /// - Returns: The lowercased ISO2 code, or `nil` when the name is missing or unknown.
    private static func nameLookup(rawName: String?, resolver: ResolverIndex) -> String? {

        guard let rawName else { return nil }

        return resolver.nameToIso2[rawName]
    }
}

// MARK: - GeoJSON Resource Cache (decoded collections)

/// Holds the decoded feature collections so the file is parsed once per run.
///
/// The decoded tree is large - around 29 MB for the bundled countries - and is only needed
/// while shapes are being built from it. It is kept anyway, because the flat map, the globe
/// and every projection ask for it separately and re-parsing costs well over a tenth of a
/// second each time. What it must not do is hold that memory while the app is in the
/// background or while the system is short of it, which is exactly when iOS decides what to
/// terminate - hence ``discardCachedCollections()`` and the observers that call it.
private actor GeoJSONResourceCache {
    static let shared = GeoJSONResourceCache()

    private var cachedCollections: [String: GeoJSON.FeatureCollection] = [:]
    private var inFlight: [String: Task<GeoJSON.FeatureCollection, Error>] = [:]

    /// Drops every decoded collection. The next request parses the file again.
    ///
    /// In-flight decodes are left alone: they have a caller waiting, and their result is
    /// cached when they finish.
    func discardCachedCollections() {
        cachedCollections.removeAll()
    }

    func featureCollection(resource: String) async throws -> GeoJSON.FeatureCollection {
        if let cached = cachedCollections[resource] { return cached }
        if let task = inFlight[resource] { return try await task.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> GeoJSON.FeatureCollection in
            guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GeoJSON.FeatureCollection.self, from: data)
        }

        inFlight[resource] = task
        do {
            let collection = try await task.value
            cachedCollections[resource] = collection
            inFlight[resource] = nil
            return collection
        } catch {
            inFlight[resource] = nil
            throw error
        }
    }
}

// MARK: - Memory pressure

extension GeoJSONLoader {

    /// Starts releasing the decoded GeoJSON when the app is backgrounded or memory runs short.
    ///
    /// Call once, at launch. The decoded collections are a cache and nothing reads them
    /// between map sessions, so giving the memory back costs only a re-parse the next time a
    /// map is opened.
    static func startReleasingCacheUnderPressure() {

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.didReceiveMemoryWarningNotification
        ]

        for name in names {
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { await GeoJSONResourceCache.shared.discardCachedCollections() }
            }
        }
    }
}

// MARK: - GeoJSON Models

nonisolated enum GeoJSON {

    struct FeatureCollection: Decodable, Sendable {
        let type: String
        let features: [Feature]
    }

    struct Feature: Decodable, Sendable {
        let type: String
        let properties: [String: JSONValue]?
        let geometry: Geometry
    }

    enum Geometry: Decodable, Sendable {
        case polygon([[[Double]]])
        case multiPolygon([[[[Double]]]])

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "Polygon":
                self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon":
                self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
            default:
                self = .polygon([])
            }
        }
    }
}

// MARK: - JSONValue

nonisolated enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let s):
            return s
        case .number(let n):
            if n.rounded() == n { return String(Int(n)) }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        default:
            return nil
        }
    }

    /// The value as a number, parsing a numeric string if that is how it was stored.
    ///
    /// Shapefile attribute tables keep everything as text, so a value that is a number in
    /// meaning can arrive either way depending on how the GeoJSON was produced.
    var doubleValue: Double? {
        switch self {
        case .number(let number):
            return number
        case .string(let string):
            return Double(string.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }
}

// MARK: - Property helpers

extension Dictionary where Key == String, Value == JSONValue {

    /// Returns the first numeric value for any of the keys, case-insensitive.
    ///
    /// - Parameter keys: Candidate keys, tried in order.
    /// - Returns: The first value that reads as a number, or `nil`.
    nonisolated func firstDouble(for keys: [String]) -> Double? {

        for key in keys {
            if let value = self[key]?.doubleValue { return value }
        }

        let lowerKeys = Set(keys.map { $0.lowercased() })
        for (key, value) in self where lowerKeys.contains(key.lowercased()) {
            if let number = value.doubleValue { return number }
        }

        return nil
    }

    /// Returns the first non-empty string value for any of the keys, case-insensitive.
    nonisolated func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue?.trimmedNonEmpty { return value }
        }

        let lowerKeys = Set(keys.map { $0.lowercased() })
        for (key, value) in self where lowerKeys.contains(key.lowercased()) {
            if let v = value.stringValue?.trimmedNonEmpty { return v }
        }
        return nil
    }
}

extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
