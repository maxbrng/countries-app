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
/// - Note: The caching itself is ``AsyncMemo``, shared with ``FlatMapShapeCache`` and the
///   decoded GeoJSON, so concurrent callers share a single build here for the same reason
///   and by the same code as everywhere else.
actor GlobeShapeCache {

    // MARK: - Shared instance

    /// Process-wide cache; the geometry is identical for every map screen.
    static let shared = GlobeShapeCache()

    // MARK: - State

    /// Built globe geometry, keyed by the level of detail it was built at.
    private let memo = AsyncMemo<GlobeShapeBuilder.Detail, [GlobeCountryShape]>()

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

        try await memo.value(for: detail) {
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(resolver: resolver)
            return GlobeShapeBuilder.buildShapes(from: resolved, detail: detail)
        }
    }
}
