//
//  FlatMapProjectionTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Countries

/// Covers ``FlatMapProjection`` at the edges of the world: the antimeridian and the poles.
///
/// Both projections must map the whole world into 0...1 on both axes, with north at y = 0,
/// because every shape, every label anchor and every hit test is expressed in that space.
struct FlatMapProjectionTests {

    /// Tolerance for a coordinate comparison. The values are computed with `log` and `tan`,
    /// so an exact comparison would be testing the standard library's rounding.
    private static let tolerance: CGFloat = 1e-9

    /// Latitude at which Web Mercator is cut off, the value the standard tile scheme uses.
    private static let mercatorLimit = 85.05112878

    private func project(_ longitude: Double,
                         _ latitude: Double,
                         _ mode: FlatMapProjectionMode) -> CGPoint {

        FlatMapProjection.projectLongitudeLatitude(longitude: longitude,
                                                   latitude: latitude,
                                                   mode: mode)
    }

    // MARK: - Antimeridian

    @Test func test_project_antimeridian_mapsToBothEdgesOfTheWorld() {

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {

            let west = project(-180, 0, mode)
            let east = project(180, 0, mode)

            #expect(abs(west.x - 0) < Self.tolerance)
            #expect(abs(east.x - 1) < Self.tolerance)
        }
    }

    @Test func test_project_primeMeridianAtEquator_isTheCentreOfTheWorld() {

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {

            let centre = project(0, 0, mode)

            #expect(abs(centre.x - 0.5) < Self.tolerance)
            #expect(abs(centre.y - 0.5) < Self.tolerance)
        }
    }

    // MARK: - Poles

    @Test func test_project_poles_inPlateCarree_reachTheTopAndBottomEdges() {

        let north = project(0, 90, .plateCarree)
        let south = project(0, -90, .plateCarree)

        #expect(abs(north.y - 0) < Self.tolerance)
        #expect(abs(south.y - 1) < Self.tolerance)
    }

    @Test func test_project_poles_inWebMercator_areClampedAndStayInsideTheWorld() {

        // Web Mercator diverges at the poles, so the projection cuts off before them. The
        // cut-off value does not divide out exactly - `mercator / .pi` lands on
        // 1.0000000000124551 - which used to put the north pole at y = -6.2e-12.
        let north = project(0, 90, .webMercator)
        let south = project(0, -90, .webMercator)

        #expect(north.y.isFinite)
        #expect(south.y.isFinite)
        #expect(north.y >= 0)
        #expect(south.y <= 1)
    }

    @Test func test_project_everyExtreme_staysInsideTheUnitSquare() {

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {
            for longitude in [-180.0, -90, 0, 90, 180] {
                for latitude in [-90.0, -85.05112878, 0, 85.05112878, 90] {

                    let point = project(longitude, latitude, mode)

                    #expect(point.x >= 0 && point.x <= 1)
                    #expect(point.y >= 0 && point.y <= 1)
                }
            }
        }
    }

    @Test func test_project_beyondTheMercatorLimit_isTheSameAsAtTheLimit() {

        let atLimit = project(0, Self.mercatorLimit, .webMercator)
        let beyond = project(0, 89, .webMercator)

        #expect(abs(atLimit.y - beyond.y) < Self.tolerance)
    }

    // MARK: - Ordering

    @Test func test_project_northIsAlwaysAboveSouth() {

        for mode in [FlatMapProjectionMode.plateCarree, .webMercator] {

            let north = project(0, 45, mode)
            let south = project(0, -45, mode)

            #expect(north.y < south.y)
        }
    }

    @Test func test_project_webMercatorCompressesTowardsThePoles() {

        // The distance from the equator to 60 degrees covers more of the map than the
        // distance from 0 to 30 does, which is the whole point of the projection.
        let thirty = project(0, 30, .webMercator).y
        let sixty = project(0, 60, .webMercator).y

        let firstBand = 0.5 - thirty
        let secondBand = thirty - sixty

        #expect(secondBand > firstBand)
    }
}
