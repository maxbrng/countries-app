//
//  FlatMapModels.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

// NOTE (Swift 6): If your target has "Default Actor Isolation" set to MainActor,
// you MUST explicitly opt out for pure data/geometry types used from background
// tasks/actors.

nonisolated enum FlatMapRenderMode: Sendable {
    case stretch
    case aspectFit
}

/// Projection selection used across Flat map components.
///
/// Swift 6 note:
/// Keep this type non-global-actor isolated so it can be used from actors/background tasks.
nonisolated enum FlatMapProjectionMode: Hashable, Sendable {
    case plateCarree
    case webMercator
}

// CGPath is not formally Sendable. We treat shapes as immutable once built.
nonisolated struct RenderCountryShape: Identifiable, @unchecked Sendable {
    let id: String
    let iso2: String
    let path: CGPath
    let labelAnchor: CGPoint
    let focusBoundingBoxNormalized: CGRect
}

extension FlatMapProjectionMode {
    nonisolated var worldAspect: CGFloat {
        switch self {
        case .plateCarree: return 2.0
        case .webMercator: return 1.0
        }
    }
}

nonisolated enum FlatMapProjection {

    nonisolated static func projectLongitudeLatitude(
        longitude: Double,
        latitude: Double,
        mode: FlatMapProjectionMode
    ) -> CGPoint {

        switch mode {

        case .plateCarree:
            let x = (longitude + 180.0) / 360.0
            let y = (90.0 - latitude) / 180.0
            return CGPoint(x: x, y: y)

        case .webMercator:
            let maxLatitude = 85.05112878
            let clampedLatitude = min(max(latitude, -maxLatitude), maxLatitude)
            let x = (longitude + 180.0) / 360.0

            let latitudeRadians = clampedLatitude * .pi / 180.0
            let mercator = log(tan(.pi / 4.0 + latitudeRadians / 2.0))
            let y = (1.0 - (mercator / .pi)) / 2.0
            return CGPoint(x: x, y: y)
        }
    }
}
