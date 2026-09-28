//
//  MapFocusTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import CoreGraphics
import Testing
@testable import Countries

/// Covers the shared currency the flat map and the globe use to hand the camera to each other.
///
/// The round trips are the point: a focus read off one renderer and applied to the same
/// renderer must come back where it started, or switching appearance twice would drift.
struct MapFocusTests {

    // MARK: - Constants

    /// Tolerance for a degree comparison. Well below a pixel at any zoom the app offers.
    private static let degreeTolerance = 1e-6

    /// Tolerance for a zoom-factor comparison.
    private static let zoomTolerance = 1e-6

    /// A viewport, world rect and fit scale that stand in for a laid-out map screen.
    private static let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
    private static let worldRect = CGRect(x: 0, y: 0, width: 400, height: 400)
    private static let fitScale: CGFloat = 2

    // MARK: - Projection inverse

    @Test func test_unproject_isTheInverseOfProject_forBothProjections() {

        // Arrange
        let coordinates: [(longitude: Double, latitude: Double)] = [
            (0, 0), (13.4, 52.5), (-74, 40.7), (151.2, -33.9), (180, 0), (-180, 0), (0, 60)
        ]

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {
            for coordinate in coordinates {

                // Act
                let projected = FlatMapProjection.projectLongitudeLatitude(
                    longitude: coordinate.longitude,
                    latitude: coordinate.latitude,
                    mode: mode
                )
                let restored = FlatMapProjection.unprojectToLongitudeLatitude(point: projected,
                                                                             mode: mode)

                // Assert
                #expect(abs(restored.longitude - coordinate.longitude) < Self.degreeTolerance)
                #expect(abs(restored.latitude - coordinate.latitude) < Self.degreeTolerance)
            }
        }
    }

    @Test func test_unproject_atTheWebMercatorCutOff_returnsTheCutOffLatitude() {

        // Arrange: the north edge of the Web Mercator world, which is not the pole.
        let topOfTheWorld = CGPoint(x: 0.5, y: 0)

        // Act
        let restored = FlatMapProjection.unprojectToLongitudeLatitude(point: topOfTheWorld,
                                                                      mode: .webMercator)

        // Assert: the documented cut-off, not 90.
        #expect(abs(restored.latitude - 85.05112878) < 1e-5)
    }

    // MARK: - Flat map round trip

    @Test func test_flatRoundTrip_returnsTheSameCamera() {

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {
            for zoom in [CGFloat(1), 2.5, 12] {

                // Arrange
                var camera = FlatMapCamera()
                camera.normalizedCenter = CGPoint(x: 0.42, y: 0.37)
                camera.userZoom = zoom

                // Act
                let focus = MapFocus.fromFlatMap(camera: camera,
                                                 viewport: Self.viewport,
                                                 worldRect: Self.worldRect,
                                                 fitScale: Self.fitScale,
                                                 projection: mode)
                let restored = focus?.flatCamera(viewport: Self.viewport,
                                                 worldRect: Self.worldRect,
                                                 fitScale: Self.fitScale,
                                                 projection: mode)

                // Assert
                let unwrapped = try? #require(restored)
                #expect(abs((unwrapped?.userZoom ?? 0) - zoom) < Self.zoomTolerance)
                #expect(abs((unwrapped?.normalizedCenter.x ?? 0) - camera.normalizedCenter.x)
                        < Self.degreeTolerance)
                #expect(abs((unwrapped?.normalizedCenter.y ?? 0) - camera.normalizedCenter.y)
                        < Self.degreeTolerance)
            }
        }
    }

    @Test func test_fromFlatMap_withAnUnlaidOutViewport_reportsNothing() {

        // Arrange: the state the map is in before its first layout pass.
        let camera = FlatMapCamera()

        // Act
        let focus = MapFocus.fromFlatMap(camera: camera,
                                         viewport: .zero,
                                         worldRect: .zero,
                                         fitScale: 0,
                                         projection: .webMercator)

        // Assert: nothing is better than a camera built from zeroes.
        #expect(focus == nil)
    }

    // MARK: - Globe round trip

    @Test func test_globeRoundTrip_returnsTheSameDistance() {

        for distance in [2_800_000.0, 8_000_000, 25_000_000] {

            // Arrange / Act
            let focus = MapFocus.fromGlobe(latitude: 52.5, longitude: 13.4, distance: distance)

            // Assert
            #expect(abs(focus.globeDistance - distance) < 1)
            #expect(focus.latitude == 52.5)
            #expect(focus.longitude == 13.4)
        }
    }

    @Test func test_span_isClampedToTheWorld() {

        // Arrange / Act: a camera further out than the whole globe, and one absurdly close.
        let tooFar = MapFocus.fromGlobe(latitude: 0, longitude: 0, distance: 400_000_000)
        let tooClose = MapFocus(latitude: 0, longitude: 0, spanDegrees: 0.0001)

        // Assert
        #expect(tooFar.spanDegrees == 360)
        #expect(tooClose.spanDegrees > 0)
        #expect(tooClose.spanDegrees < 1)
    }

    @Test func test_theWholeGlobe_isAFullTurnOfTheWorld() {

        // Arrange / Act: the distance ``GlobeMapView`` opens at.
        let focus = MapFocus.fromGlobe(latitude: 20, longitude: 0, distance: 25_000_000)

        // Assert: the calibration anchor the conversion is built on.
        #expect(focus.spanDegrees == 360)
    }
}
