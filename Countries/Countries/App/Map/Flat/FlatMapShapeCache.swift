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
        /// Full detail, used once the camera is zoomed past ``FlatMapViewModel/detailZoomThreshold``.
        case full
        /// World view detail: every vertex the screen can resolve at that scale.
        case overview
        /// Reduced detail, used by the non-interactive preview map.
        case light
    }

    /// Cache key: one entry per projection and variant combination.
    private struct Key: Hashable, Sendable {
        let projection: FlatMapProjectionMode
        let variant: Variant
    }

    // MARK: - State

    /// Finished geometry sets, one per projection and variant.
    ///
    /// - Note: The caching itself is ``AsyncMemo``, shared with ``GlobeShapeCache`` and the
    ///   decoded GeoJSON. Concurrent callers await the same build rather than projecting the
    ///   world twice, by the same code in all three places.
    private let memo = AsyncMemo<Key, [RenderCountryShape]>()

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

        return try await memo.value(for: key) {
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(
                resolver: resolver,
                keySet: .init()
            )

            let builderVariant: FlatPathBuilder.Variant = switch variant {
            case .full: .full
            case .overview: .overview
            case .light: .light
            }

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
                        boundsNormalized: result.path.boundingBoxOfPath,
                        labelInfo: Self.labelInfo(from: feature.properties,
                                                  projectionMode: projectionMode,
                                                  fitBox: result.labelFitBoundingBox)
                    )
                )
            }
            return built
        }
    }

    /// Drops all cached geometry, forcing the next request to rebuild.
    func clearAll() async {
        await memo.discardAll()
    }

    // MARK: - Label hints

    /// Keys under which Natural Earth ships its label hints.
    private enum LabelKeys {
        static let rank = ["labelrank", "LABELRANK"]
        static let abbreviation = ["abbrev", "ABBREV"]
        static let anchorLongitude = ["label_x", "LABEL_X"]
        static let anchorLatitude = ["label_y", "LABEL_Y"]
        static let minimumZoom = ["min_label", "MIN_LABEL"]
        static let maximumZoom = ["max_label", "MAX_LABEL"]
    }

    /// Reads one feature's label hints out of its properties.
    ///
    /// - Parameters:
    ///   - properties: The feature's raw property bag.
    ///   - projectionMode: Projection the shapes are built in, so the anchor lands in the
    ///     same space as the geometry.
    ///   - fitBox: The country's own bounds. An anchor outside them is discarded: a few
    ///     multi-part countries carry one that sits in the sea next to the mainland.
    /// - Returns: The hints that are present, with ``LabelInfo/unknown`` values for the rest.
    private static func labelInfo(from properties: [String: JSONValue],
                                  projectionMode: FlatMapProjectionMode,
                                  fitBox: CGRect) -> LabelInfo {

        let rank = properties.firstDouble(for: LabelKeys.rank)
            .map { Int($0.rounded()) } ?? LabelInfo.leastImportantRank

        let abbreviation = properties.firstString(for: LabelKeys.abbreviation)

        var anchor: CGPoint?
        if let longitude = properties.firstDouble(for: LabelKeys.anchorLongitude),
           let latitude = properties.firstDouble(for: LabelKeys.anchorLatitude) {

            let projected = FlatMapProjection.projectLongitudeLatitude(longitude: longitude,
                                                                       latitude: latitude,
                                                                       mode: projectionMode)
            if fitBox.contains(projected) { anchor = projected }
        }

        return LabelInfo(rank: rank,
                         abbreviation: abbreviation,
                         anchor: anchor,
                         minimumZoomLevel: properties.firstDouble(for: LabelKeys.minimumZoom),
                         maximumZoomLevel: properties.firstDouble(for: LabelKeys.maximumZoom))
    }

}
