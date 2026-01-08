//
//  GlobeShapeBuilder.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import MapKit

struct GlobeCountryShape: Identifiable, Sendable {
    let id: String
    let iso2: String
    let polygons: [[CLLocationCoordinate2D]]
    let center: CLLocationCoordinate2D
    let boundingBox: MKMapRect
}

enum GlobeShapeBuilder {

    static func buildShapes(from resolved: [GeoJSONLoader.ResolvedFeature]) -> [GlobeCountryShape] {
        
        resolved.compactMap { feature in
            
            let polygons = toCoordinates(geometry: feature.geometry)
            guard !polygons.isEmpty else { return nil }

            let (center, boundingBox) = computeCenterAndBoundingBox(polygons: polygons)

            return GlobeCountryShape(
                id: feature.iso2,
                iso2: feature.iso2,
                polygons: polygons,
                center: center,
                boundingBox: boundingBox
            )
        }
    }

    // MARK: - GeoJSON -> MapKit

    private static func toCoordinates(geometry: GeoJSON.Geometry) -> [[CLLocationCoordinate2D]] {
        
        switch geometry {
        case .polygon(let rings):
            return rings.map { $0.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) } }
            
        case .multiPolygon(let polygons):
            return polygons.flatMap { $0.map { $0.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) } } }
        }
    }

    // MARK: - Derived data

    private static func computeCenterAndBoundingBox(polygons: [[CLLocationCoordinate2D]]) -> (CLLocationCoordinate2D, MKMapRect) {
        // Pick the "mainland" ring as the one with the most points (same behavior as original code).
        let mainlandRing = polygons.max(by: { $0.count < $1.count }) ?? polygons[0]

        let centerLatitude = mainlandRing.map(\.latitude).reduce(0, +) / Double(mainlandRing.count)
        let centerLongitude = mainlandRing.map(\.longitude).reduce(0, +) / Double(mainlandRing.count)
        let center = CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)

        let mapPoints = polygons.flatMap { $0 }.map(MKMapPoint.init)
        let minX = mapPoints.map(\.x).min() ?? 0
        let maxX = mapPoints.map(\.x).max() ?? 0
        let minY = mapPoints.map(\.y).min() ?? 0
        let maxY = mapPoints.map(\.y).max() ?? 0

        let boundingBox = MKMapRect(x: minX,
                                    y: minY,
                                    width: maxX - minX,
                                    height: maxY - minY)
        
        return (center, boundingBox)
    }
}
