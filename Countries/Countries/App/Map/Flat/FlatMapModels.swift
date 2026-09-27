//
//  FlatMapModels.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

// MARK: - Render mode

/// How the projected world is sized inside the available viewport.
///
/// - Note: Swift 6. This target has "Default Actor Isolation" set to MainActor, so pure
///   data and geometry types that are used from background tasks or actors MUST
///   explicitly opt out. That is why every type in this file is `nonisolated`.
nonisolated enum FlatMapRenderMode: Sendable {
    /// Fills the viewport completely, ignoring the projection's aspect ratio.
    case stretch
    /// Keeps the projection's aspect ratio and centers the letterboxed world.
    case aspectFit
}

// MARK: - Projection mode

/// Projection selection used across Flat map components.
///
/// Swift 6 note:
/// Keep this type non-global-actor isolated so it can be used from actors/background tasks.
nonisolated enum FlatMapProjectionMode: Hashable, Sendable {
    /// Equirectangular projection: longitude and latitude map linearly, 2:1 world.
    case plateCarree
    /// Web Mercator projection: square world, latitude compressed towards the poles.
    case webMercator
}

extension FlatMapProjectionMode {

    /// Width-to-height ratio of the projected world for this projection.
    ///
    /// Used to letterbox the world inside the viewport in ``FlatMapRenderMode/aspectFit``.
    /// Plate carree spans 360 degrees of longitude over 180 degrees of latitude (2:1);
    /// Web Mercator normalizes both axes to the same range (1:1).
    nonisolated var worldAspect: CGFloat {
        switch self {
        case .plateCarree: return 2.0
        case .webMercator: return 1.0
        }
    }
}

// MARK: - Render shapes

/// One country's drawable geometry, prepared once per projection and variant.
///
/// - Note: `CGPath` is not formally `Sendable`. We treat shapes as immutable once built.
nonisolated struct RenderCountryShape: Identifiable, @unchecked Sendable {

    /// Stable identity for SwiftUI; the country's lowercased ISO2 code.
    let id: String

    /// Lowercased ISO2 code this geometry belongs to.
    let iso2: String

    /// Built in normalized world space (0...1 on both axes).
    let path: CGPath

    /// Where a label for this country is anchored, in normalized world space.
    let labelAnchor: CGPoint

    /// Bounds of the largest ring, which is what the camera frames when focusing.
    let focusBoundingBoxNormalized: CGRect

    /// Bounds of the *whole* path including outlying islands. Hit-test prefilter.
    let boundsNormalized: CGRect
}

// MARK: - Shape requests

/// Identifies one built geometry set. Used as a `.task(id:)` key and to warm the
/// cache ahead of time.
nonisolated struct ShapeRequest: Hashable, Sendable {

    /// Projection the geometry is built for.
    let projection: FlatMapProjectionMode

    /// Level of detail the geometry is simplified to.
    let variant: FlatMapShapeCache.Variant

    /// What the interactive map screen renders. Kept here so the prefetch on the
    /// main screen cannot silently drift away from what the map actually asks for.
    static let interactiveMap = ShapeRequest(projection: .webMercator, variant: .full)
}

// MARK: - Projection math

/// Stateless conversion from geographic coordinates into normalized world space.
nonisolated enum FlatMapProjection {

    /// Projects a geographic coordinate into normalized world space.
    /// - Parameters:
    ///   - longitude: Longitude in degrees, -180...180.
    ///   - latitude: Latitude in degrees, -90...90. Clamped for ``FlatMapProjectionMode/webMercator``.
    ///   - mode: Projection to apply.
    /// - Returns: A point in 0...1 on both axes, with y growing downwards (north at y = 0).
    nonisolated static func projectLongitudeLatitude(
        longitude: Double,
        latitude: Double,
        mode: FlatMapProjectionMode
    ) -> CGPoint {

        switch mode {

        case .plateCarree:
            let normalizedX = (longitude + 180.0) / 360.0
            let normalizedY = (90.0 - latitude) / 180.0
            return CGPoint(x: normalizedX, y: normalizedY)

        case .webMercator:
            // Latitude limit of Web Mercator: the projection diverges towards the
            // poles, so it is cut off at the value the standard tile scheme uses.
            let maxLatitude = 85.05112878
            let clampedLatitude = min(max(latitude, -maxLatitude), maxLatitude)
            let normalizedX = (longitude + 180.0) / 360.0

            let latitudeRadians = clampedLatitude * .pi / 180.0
            let mercator = log(tan(.pi / 4.0 + latitudeRadians / 2.0))
            let normalizedY = (1.0 - (mercator / .pi)) / 2.0
            return CGPoint(x: normalizedX, y: normalizedY)
        }
    }
}
