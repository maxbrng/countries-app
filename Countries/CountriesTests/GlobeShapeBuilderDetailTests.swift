//
//  GlobeShapeBuilderDetailTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Testing
@testable import Countries

/// Guards the rule that keeps the zoomed-out globe from growing a halo.
///
/// The overlays are stroked at a fixed width in points, so a ring smaller than that width is
/// not drawn as a shape - it is drawn as a blob of stroke. At the globe's opening distance 877
/// of the 1,329 rings in the bundled data are smaller than a single pixel, and a selected
/// United States turned into a star of them scattered across the Pacific.
struct GlobeShapeBuilderDetailTests {

    // MARK: - Helpers

    /// Longitude and latitude span of one pixel at the globe's opening distance, in degrees.
    private static let onePixelInDegrees = 0.51

    /// Builds a square ring of `size` degrees, offset so it cannot overlap another.
    ///
    /// - Parameters:
    ///   - size: Edge length in degrees.
    ///   - longitude: Longitude of the ring's lower left corner.
    /// - Returns: A closed ring in GeoJSON coordinate order.
    private func square(size: Double, atLongitude longitude: Double) -> [[Double]] {
        [
            [longitude, 0],
            [longitude + size, 0],
            [longitude + size, size],
            [longitude, size],
            [longitude, 0]
        ]
    }

    /// One feature holding a mainland and a scattering of sub-pixel islands.
    ///
    /// - Parameter islandCount: How many islands to add beside the mainland.
    /// - Returns: A resolved feature ready for ``GlobeShapeBuilder``.
    private func feature(islandCount: Int) -> GeoJSONLoader.ResolvedFeature {

        let mainland = [square(size: 20, atLongitude: -100)]
        let islands = (0..<islandCount).map { index in
            [square(size: Self.onePixelInDegrees / 2, atLongitude: Double(index) * 2)]
        }

        return GeoJSONLoader.ResolvedFeature(iso2: "us",
                                             geometry: .multiPolygon([mainland] + islands),
                                             properties: [:])
    }

    // MARK: - Tests

    @Test func test_farDetail_dropsRingsSmallerThanAPixel() {

        let built = GlobeShapeBuilder.buildShapes(from: [feature(islandCount: 60)], detail: .far)

        #expect(built.count == 1)
        #expect(built.first?.polygons.count == 1)
    }

    @Test func test_nearDetail_keepsTheSameIslands() {

        let built = GlobeShapeBuilder.buildShapes(from: [feature(islandCount: 60)], detail: .near)

        #expect(built.first?.polygons.count == 61)
    }

    @Test func test_farDetail_neverDropsACountryThatIsOnlyIslands() {

        let islandsOnly = GeoJSONLoader.ResolvedFeature(
            iso2: "mv",
            geometry: .multiPolygon([[square(size: Self.onePixelInDegrees / 4, atLongitude: 73)]]),
            properties: [:]
        )

        let built = GlobeShapeBuilder.buildShapes(from: [islandsOnly], detail: .far)

        // The largest ring is kept whatever its size: a country made of nothing but sub-pixel
        // islands would otherwise disappear from the globe entirely.
        #expect(built.count == 1)
        #expect(built.first?.polygons.count == 1)
    }
}
