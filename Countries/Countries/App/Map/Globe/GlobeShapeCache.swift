//
//  GlobeShapeCache.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import Foundation

/// Builds the globe geometry once, off the main actor, and hands out the cached
/// result afterwards. Previously ``GlobeShapeBuilder`` ran on the MainActor on every
/// appearance switch, which is what froze the UI when entering 3D.
///
/// - Note: Concurrent callers share a single build: the second caller awaits the in-flight
///   task instead of starting a second one.
actor GlobeShapeCache {

    // MARK: - Shared instance

    /// Process-wide cache; the geometry is identical for every map screen.
    static let shared = GlobeShapeCache()

    // MARK: - State

    /// Result of the completed build, kept for the lifetime of the process.
    private var cachedShapes: [GlobeCountryShape]?

    /// Build currently running, used to de-duplicate overlapping requests.
    private var inFlight: Task<[GlobeCountryShape], Error>?

    // MARK: - Access

    /// Returns the globe geometry, building it off the main actor on first use.
    ///
    /// - Parameter resolver: `Sendable` iso2 lookup table from ``CountryIndex``, used instead of
    ///   the SwiftData ``Country`` models, which must never cross into background work.
    /// - Returns: The cached shapes, or the freshly built ones on first call.
    /// - Throws: Whatever ``GeoJSONLoader`` throws while reading or decoding the bundled GeoJSON.
    func shapes(resolver: GeoJSONLoader.ResolverIndex) async throws -> [GlobeCountryShape] {

        if let cachedShapes { return cachedShapes }
        if let inFlight { return try await inFlight.value }

        let task = Task.detached(priority: .userInitiated) { () async throws -> [GlobeCountryShape] in
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(resolver: resolver)
            return GlobeShapeBuilder.buildShapes(from: resolved)
        }

        inFlight = task

        do {
            let shapes = try await task.value
            cachedShapes = shapes
            inFlight = nil
            return shapes
        } catch {
            inFlight = nil
            throw error
        }
    }
}
