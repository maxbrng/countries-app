//
//  GlobeShapeBuilder.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import MapKit
import CoreGraphics

// MARK: - Models

/// One renderable ring plus its own bounding rect.
///
/// Bounds are stored *per polygon* on purpose: a single bounding rect per country
/// spans almost the whole world for anything crossing the antimeridian
/// (US, RU, FJ, NZ, KI, AQ), which made those countries match every tap.
nonisolated struct GlobePolygon: Sendable {

    /// Ring coordinates in drawing order, ready to hand to `MapPolygon`.
    let coordinates: [CLLocationCoordinate2D]

    /// Bounding rect of ``coordinates``, used as the cheap first pass during hit testing.
    let mapRect: MKMapRect
}

/// All rings of a single country, plus the framing data the globe camera needs.
///
/// - Note: ``iso2`` is lowercased, matching the keys used by ``CountryIndex`` and the
///   GeoJSON resolution in ``GeoJSONLoader``.
nonisolated struct GlobeCountryShape: Identifiable, Sendable {

    /// Stable identity for `ForEach`; equal to ``iso2``.
    let id: String

    /// Lowercased ISO 3166-1 alpha-2 code of the country.
    let iso2: String

    /// Every ring that survived simplification, largest first.
    let polygons: [GlobePolygon]

    /// Centroid of the largest ring: the "mainland" the camera should frame.
    let center: CLLocationCoordinate2D

    /// Bounds of the largest ring, used to derive the camera distance.
    let focusRect: MKMapRect
}

// MARK: - Builder

/// Turns resolved GeoJSON features into the polygon overlays the 3D globe draws.
///
/// - Note: Runs off the main actor through ``GlobeShapeCache``; every type it touches is
///   `Sendable` so the work can happen in a detached task.
nonisolated enum GlobeShapeBuilder {

    // MARK: - Constants

    /// Max deviation in degrees. ~0.08° ≈ 9 km, invisible at globe scale.
    private static let simplificationTolerance: CGFloat = 0.08

    /// Rings smaller than this (deg²) are dropped, unless it is the only ring.
    private static let minimumRingArea: CGFloat = 0.02

    /// Fewest points that still describe an area; anything below is a point or a line.
    private static let minimumRingPointCount: Int = 3

    /// Number of values a GeoJSON coordinate pair must have: longitude and latitude.
    /// Entries may carry a third elevation value, which is ignored.
    private static let coordinateComponentCount: Int = 2

    /// Latitude bound used to clamp derived centroids into the valid range.
    private static let maximumLatitude: CLLocationDegrees = 90

    /// Longitude bound used to clamp derived centroids into the valid range.
    private static let maximumLongitude: CLLocationDegrees = 180

    // MARK: - Shape building

    /// Builds one ``GlobeCountryShape`` per feature that has usable geometry.
    ///
    /// Per feature the outer rings are ranked by area, tiny rings are dropped, the survivors are
    /// simplified to ``simplificationTolerance`` and the largest ring supplies the camera centre
    /// and focus rect.
    ///
    /// - Parameter resolved: Features already matched to an iso2 code by ``GeoJSONLoader``.
    /// - Returns: The renderable shapes; features without a usable ring are skipped.
    static func buildShapes(from resolved: [GeoJSONLoader.ResolvedFeature]) -> [GlobeCountryShape] {

        resolved.compactMap { feature in

            let rings = outerRings(of: feature.geometry)
            guard !rings.isEmpty else { return nil }

            // Largest ring first so the mainland is easy to pick out.
            let ranked = rings
                .map { (ring: $0, area: PolylineSimplifier.ringArea($0)) }
                .sorted { $0.area > $1.area }

            guard let mainland = ranked.first else { return nil }

            let kept = ranked.enumerated().filter { index, entry in
                index == 0 || entry.area >= minimumRingArea
            }

            let polygons: [GlobePolygon] = kept.compactMap { _, entry in

                let simplified = PolylineSimplifier.simplify(entry.ring,
                                                             tolerance: simplificationTolerance)
                guard simplified.count >= minimumRingPointCount else { return nil }

                let coordinates = simplified.map {
                    CLLocationCoordinate2D(latitude: $0.y, longitude: $0.x)
                }

                return GlobePolygon(coordinates: coordinates,
                                    mapRect: mapRect(for: coordinates))
            }

            guard !polygons.isEmpty else { return nil }

            let mainlandCoordinates = mainland.ring.map {
                CLLocationCoordinate2D(latitude: $0.y, longitude: $0.x)
            }

            return GlobeCountryShape(
                id: feature.iso2,
                iso2: feature.iso2,
                polygons: polygons,
                center: centroid(of: mainland.ring),
                focusRect: mapRect(for: mainlandCoordinates)
            )
        }
    }

    // MARK: - Geometry extraction

    /// Only outer rings. Interior rings would otherwise be filled as solid land,
    /// painting over enclaves such as Lesotho, San Marino and the Vatican.
    ///
    /// - Parameter geometry: Polygon or multi-polygon geometry of one GeoJSON feature.
    /// - Returns: One point ring per polygon, with `x` holding longitude and `y` latitude.
    private static func outerRings(of geometry: GeoJSON.Geometry) -> [[CGPoint]] {

        func toPoints(_ ring: [[Double]]) -> [CGPoint] {
            ring.compactMap { pair in
                guard pair.count >= Self.coordinateComponentCount else { return nil }
                return CGPoint(x: pair[0], y: pair[1])
            }
        }

        switch geometry {
        case .polygon(let rings):
            guard let outer = rings.first else { return [] }
            return [toPoints(outer)]

        case .multiPolygon(let polygons):
            return polygons.compactMap { polygon in
                guard let outer = polygon.first else { return nil }
                return toPoints(outer)
            }
        }
    }

    // MARK: - Derived data

    /// Area-weighted polygon centroid, falling back to the bounding-box centre
    /// for degenerate rings. A plain average of the coordinates would be pulled
    /// toward whichever stretch of coastline happens to carry the most points.
    ///
    /// The shoelace formula accumulates the signed cross product of consecutive edges; the
    /// coordinate sums weighted by that cross product divided by three times the signed area
    /// give the centroid.
    ///
    /// - Parameter ring: Closed ring in degrees, `x` longitude and `y` latitude.
    /// - Returns: The centroid, clamped to the valid latitude and longitude range.
    private static func centroid(of ring: [CGPoint]) -> CLLocationCoordinate2D {

        guard ring.count >= minimumRingPointCount else {
            let first = ring.first ?? .zero
            return CLLocationCoordinate2D(latitude: first.y, longitude: first.x)
        }

        var doubleArea: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0

        for index in ring.indices {
            let current = ring[index]
            let next = ring[(index + 1) % ring.count]
            let cross = current.x * next.y - next.x * current.y
            doubleArea += cross
            x += (current.x + next.x) * cross
            y += (current.y + next.y) * cross
        }

        // A zero signed area means the ring is collinear or self-cancelling, so the
        // shoelace centroid is undefined and the bounding-box centre is used instead.
        guard abs(doubleArea) > .ulpOfOne else {
            let minX = ring.map(\.x).min() ?? 0
            let maxX = ring.map(\.x).max() ?? 0
            let minY = ring.map(\.y).min() ?? 0
            let maxY = ring.map(\.y).max() ?? 0
            return CLLocationCoordinate2D(latitude: Double((minY + maxY) / 2),
                                          longitude: Double((minX + maxX) / 2))
        }

        let factor = 1 / (3 * doubleArea)

        return CLLocationCoordinate2D(
            latitude: Double(y * factor).clamped(-maximumLatitude, maximumLatitude),
            longitude: Double(x * factor).clamped(-maximumLongitude, maximumLongitude)
        )
    }

    /// Bounding rect of a coordinate list in projected map space.
    ///
    /// - Parameter coordinates: Coordinates to enclose.
    /// - Returns: The union of all coordinates as an `MKMapRect`, or `.null` when empty.
    private static func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {

        guard let first = coordinates.first else { return .null }

        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))

        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }

        return rect
    }
}
