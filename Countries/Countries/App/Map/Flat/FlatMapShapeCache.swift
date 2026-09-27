//
//  FlatMapShapeCache.swift
//  Countries
//
//  Created by Max Breuning on 24.01.26.
//

import Foundation
import CoreGraphics

/// Caches the built country geometry per projection and level of detail.
///
/// Building the shapes means decoding the bundled GeoJSON and projecting every ring,
/// which is far too expensive to repeat per appearance. The actor keeps one entry per
/// projection times variant and de-duplicates builds that are already in flight, so
/// two views asking for the same geometry at the same time share a single build.
///
/// - Note: An actor on purpose: ``RenderCountryShape`` is `Sendable`, the SwiftData
///   models are not and never reach this type.
actor FlatMapShapeCache {

    // MARK: - Shared instance

    /// Process-wide cache. The built geometry is identical for every map on screen.
    static let shared = FlatMapShapeCache()

    // MARK: - Nested types

    /// Level of detail the geometry is simplified to.
    enum Variant: Hashable, Sendable {
        /// Full detail, used by the interactive map.
        case full
        /// Reduced detail, used by the non-interactive preview map.
        case light
    }

    /// Cache key: one entry per projection and variant combination.
    private struct Key: Hashable {
        let projection: FlatMapProjectionMode
        let variant: Variant
    }

    // MARK: - State

    /// Finished geometry sets, kept for the lifetime of the process.
    private var cache: [Key: [RenderCountryShape]] = [:]

    /// Builds that have started but not finished, so concurrent callers can await
    /// the same task instead of projecting the world twice.
    private var inFlight: [Key: Task<[RenderCountryShape], Error>] = [:]

    // MARK: - Access

    /// Builds a variant into the cache without needing its result.
    ///
    /// The preview on the main screen uses (plateCarree, light) while the
    /// interactive map uses (webMercator, full): different keys, so nothing is
    /// shared. Warming the interactive combination while the user is still on the
    /// main screen turns the first tap into a cache hit.
    ///
    /// - Parameters:
    ///   - projectionMode: Projection to build for.
    ///   - resolver: Feature-to-ISO2 lookup table handed to ``GeoJSONLoader``.
    ///   - variant: Level of detail to build.
    /// - Note: Failures are swallowed on purpose; a warm-up that does not finish only
    ///   means the real request later has to build the geometry itself.
    func warm(projectionMode: FlatMapProjectionMode,
              resolver: GeoJSONLoader.ResolverIndex,
              variant: Variant) async {
        _ = try? await shapes(projectionMode: projectionMode, resolver: resolver, variant: variant)
    }

    /// Returns the built geometry for one projection and variant, building it on first use.
    /// - Parameters:
    ///   - projectionMode: Projection the paths are built in.
    ///   - resolver: Feature-to-ISO2 lookup table handed to ``GeoJSONLoader``.
    ///   - variant: Level of detail to build.
    /// - Returns: One ``RenderCountryShape`` per resolved feature, in file order.
    /// - Throws: Whatever decoding the bundled GeoJSON throws.
    func shapes(
        projectionMode: FlatMapProjectionMode,
        resolver: GeoJSONLoader.ResolverIndex,
        variant: Variant
    ) async throws -> [RenderCountryShape] {

        let key = Key(projection: projectionMode, variant: variant)

        if let cached = cache[key] { return cached }
        if let inflight = inFlight[key] { return try await inflight.value }

        let task = Task.detached(priority: .userInitiated) { () async throws -> [RenderCountryShape] in
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(
                resolver: resolver,
                keySet: .init()
            )

            let builderVariant: FlatPathBuilder.Variant = (variant == .full ? .full : .light)

            var built: [RenderCountryShape] = []
            built.reserveCapacity(resolved.count)

            for feature in resolved {
                let result = FlatPathBuilder.build(
                    from: feature.geometry,
                    projectionMode: projectionMode,
                    iso2: feature.iso2,
                    variant: builderVariant
                )

                built.append(
                    RenderCountryShape(
                        id: feature.iso2,
                        iso2: feature.iso2,
                        path: result.path,
                        labelAnchor: result.labelAnchor,
                        focusBoundingBoxNormalized: result.focusBoundingBox,
                        labelFitBoundingBoxNormalized: result.labelFitBoundingBox,
                        boundsNormalized: result.path.boundingBoxOfPath
                    )
                )
            }
            return built
        }

        inFlight[key] = task
        do {
            let shapes = try await task.value
            cache[key] = shapes
            inFlight[key] = nil
            return shapes
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// Drops all cached and in-flight geometry, forcing the next request to rebuild.
    func clearAll() {
        cache.removeAll()
        inFlight.removeAll()
    }
}
