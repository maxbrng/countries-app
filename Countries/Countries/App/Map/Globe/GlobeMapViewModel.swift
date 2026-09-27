//
//  GlobeMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import Observation
import SwiftData
import MapKit

/// Owns the globe's geometry and answers hit tests for ``GlobeMapView``.
///
/// The geometry is loaded once through ``GlobeShapeCache`` and then reused; the country index is
/// refreshed independently whenever the underlying ``Country`` models change.
@Observable
@MainActor
final class GlobeMapViewModel {

    // MARK: - State

    /// Renderable country geometry, empty until ``loadShapesIfNeeded()`` has succeeded.
    private(set) var shapes: [GlobeCountryShape] = []

    /// Lookup from lowercased iso2 to ``Country``, used for colouring and selection.
    private(set) var countryIndex: CountryIndex = .init(countries: [])

    /// Whether the geometry is still being built. Starts as `true`.
    private(set) var isLoading: Bool = true

    private var didLoadShapes = false

    // MARK: - Loading

    /// Shapes are geometry only, so a status change must never rebuild them.
    ///
    /// - Parameter countries: Current countries from the SwiftData query.
    func updateCountryIndex(countries: [Country]) {
        countryIndex = CountryIndex(countries: countries)
    }

    /// Loads the globe geometry on first call and no-ops afterwards.
    ///
    /// - Note: On failure ``shapes`` is reset to empty and ``isLoading`` still ends up `false`,
    ///   so the globe shows MapKit's own borders without overlays instead of a stuck spinner.
    func loadShapesIfNeeded() async {

        guard !didLoadShapes else {
            isLoading = false
            return
        }

        isLoading = true

        do {
            let resolver = countryIndex.resolverIndex
            shapes = try await GlobeShapeCache.shared.shapes(resolver: resolver)
            didLoadShapes = true
        } catch {
            shapes = []
        }

        isLoading = false
    }

    // MARK: - Hit testing

    /// Tests the tapped coordinate against each polygon's own bounds first,
    /// so only the handful of genuinely overlapping rings get the expensive check.
    ///
    /// - Parameter coordinate: Coordinate the user tapped.
    /// - Returns: The first shape containing the coordinate, or `nil` for a tap on open water.
    func country(at coordinate: CLLocationCoordinate2D) -> GlobeCountryShape? {

        let mapPoint = MKMapPoint(coordinate)

        return shapes.first { shape in
            shape.polygons.contains { polygon in
                polygon.mapRect.contains(mapPoint)
                    && Self.isCoordinate(coordinate, inside: polygon.coordinates)
            }
        }
    }

    /// Ray-casting point-in-polygon test.
    ///
    /// Walks every edge and counts how many of them a ray cast east from the probe crosses; an
    /// odd number of crossings means the probe lies inside. Edges that do not span the probe's
    /// latitude cannot be crossed and are skipped, as are horizontal edges, whose intersection
    /// is undefined.
    ///
    /// - Parameters:
    ///   - probe: Coordinate to test.
    ///   - polygon: Closed ring to test against.
    /// - Returns: `true` when the probe lies inside the ring.
    /// - Note: Works in unprojected degrees and therefore does not handle rings crossing the
    ///   antimeridian; those are split per polygon before they reach this method.
    static func isCoordinate(_ probe: CLLocationCoordinate2D,
                             inside polygon: [CLLocationCoordinate2D]) -> Bool {

        var isInside = false
        var previousIndex = polygon.count - 1

        for index in 0..<polygon.count {
            let current = polygon[index]
            let previous = polygon[previousIndex]

            let crossesLatitude =
                (current.latitude > probe.latitude) != (previous.latitude > probe.latitude)

            if crossesLatitude {
                let denominator = previous.latitude - current.latitude

                guard abs(denominator) > .ulpOfOne else {
                    previousIndex = index
                    continue
                }

                let longitudeAtProbe = current.longitude
                    + (probe.latitude - current.latitude) / denominator
                    * (previous.longitude - current.longitude)

                if longitudeAtProbe > probe.longitude { isInside.toggle() }
            }
            previousIndex = index
        }

        return isInside
    }
}
