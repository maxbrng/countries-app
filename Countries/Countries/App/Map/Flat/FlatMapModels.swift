//
//  FlatMapModels.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

enum FlatMapRenderMode: Sendable {
    case stretch
    case aspectFit
}

enum FlatMapProjectionMode: Equatable, Sendable {
    case plateCarree
    case webMercator
}

struct RenderCountryShape: Identifiable, Sendable {
    let id: String
    let iso2: String
    let path: CGPath
    let labelAnchor: CGPoint
    let focusBoundingBoxNormalized: CGRect
}

extension FlatMapProjectionMode {
    var worldAspect: CGFloat {
        switch self {
        case .plateCarree: return 2.0
        case .webMercator: return 1.0
        }
    }
}

enum FlatMapProjection {
    
    static func projectLongitudeLatitude(longitude: Double,
                                         latitude: Double,
                                         mode: FlatMapProjectionMode) -> CGPoint {
        
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
