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

    /// Completed builds, kept for the lifetime of the process, one per detail level.
    private var cachedShapes: [GlobeShapeBuilder.Detail: [GlobeCountryShape]] = [:]

    /// Builds currently running, used to de-duplicate overlapping requests.
    private var inFlight: [GlobeShapeBuilder.Detail: Task<[GlobeCountryShape], Error>] = [:]

    // MARK: - Access

    /// Returns the globe geometry, building it off the main actor on first use.
    ///
    /// - Parameters:
    ///   - resolver: `Sendable` iso2 lookup table from ``CountryIndex``, used instead of the
    ///     SwiftData ``Country`` models, which must never cross into background work.
    ///   - detail: Which level of detail to build. See ``GlobeShapeBuilder/Detail``.
    /// - Returns: The cached shapes, or the freshly built ones on first call.
    /// - Throws: Whatever ``GeoJSONLoader`` throws while reading or decoding the bundled GeoJSON.
    func shapes(resolver: GeoJSONLoader.ResolverIndex,
                detail: GlobeShapeBuilder.Detail) async throws -> [GlobeCountryShape] {

        if let cached = cachedShapes[detail] { return cached }
        if let running = inFlight[detail] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) { () async throws -> [GlobeCountryShape] in
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(resolver: resolver)
            return GlobeShapeBuilder.buildShapes(from: resolved, detail: detail)
        }

        inFlight[detail] = task

        do {
            let shapes = try await task.value
            cachedShapes[detail] = shapes
            inFlight[detail] = nil
            return shapes
        } catch {
            inFlight[detail] = nil
            throw error
        }
    }
}
