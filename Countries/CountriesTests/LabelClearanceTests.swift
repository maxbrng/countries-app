//
//  LabelClearanceTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 01.10.26.
//

import CoreGraphics
import Testing
@testable import Countries

/// Guards the measurement that decides whether a country's name may be drawn.
///
/// The label pass used to ask whether the name fit the *bounding box* of a country. A box says
/// nothing about the land inside it: Croatia's box is wide while the country under it is a
/// narrow crescent, so its name passed the test and then sat outside the border. The builder
/// now reports the radius of the largest circle that fits inside the outline at the anchor.
///
/// The renderer asks that circle only whether the text's *height* fits, and asks the outline's
/// unpadded bounding box whether the country spans enough of the name's width. Demanding that
/// the whole text rectangle fit inside the circle was tried and left the map almost empty -
/// "Germany" needed a 4.3x zoom - because no country holds a name the way a box holds one.
struct LabelClearanceTests {

    // MARK: - Helpers

    /// Builds a polygon geometry from rings given in longitude/latitude order.
    ///
    /// - Parameter rings: Outer ring first, as GeoJSON orders them.
    /// - Returns: The geometry ``FlatPathBuilder`` consumes.
    private func geometry(_ rings: [[[Double]]]) -> GeoJSON.Geometry {
        .polygon(rings)
    }

    /// A square centred on the equator and the prime meridian.
    ///
    /// - Parameter halfSpan: Half the edge length, in degrees.
    /// - Returns: A closed ring.
    private func square(halfSpan: Double) -> [[Double]] {
        [
            [-halfSpan, -halfSpan],
            [ halfSpan, -halfSpan],
            [ halfSpan,  halfSpan],
            [-halfSpan,  halfSpan],
            [-halfSpan, -halfSpan]
        ]
    }

    /// A wide, thin horizontal bar: the shape whose bounding box lies about it most.
    ///
    /// - Parameters:
    ///   - halfWidth: Half the bar's width, in degrees.
    ///   - halfHeight: Half its height, in degrees.
    /// - Returns: A closed ring.
    private func bar(halfWidth: Double, halfHeight: Double) -> [[Double]] {
        [
            [-halfWidth, -halfHeight],
            [ halfWidth, -halfHeight],
            [ halfWidth,  halfHeight],
            [-halfWidth,  halfHeight],
            [-halfWidth, -halfHeight]
        ]
    }

    /// Builds one shape and returns what it reports about its room for a label.
    ///
    /// - Parameter rings: The geometry's rings.
    /// - Returns: The clearance in normalized world units.
    private func clearance(of rings: [[[Double]]]) -> CGFloat {
        FlatPathBuilder.build(from: geometry(rings),
                              projectionMode: .plateCarree,
                              iso2: "xx",
                              variant: .full).labelClearance
    }

    // MARK: - Tests

    @Test func test_clearance_ofASquare_growsWithTheSquare() {

        let small = clearance(of: [square(halfSpan: 5)])
        let large = clearance(of: [square(halfSpan: 10)])

        // Twice the country, twice the room. The assertions are relative on purpose: what the
        // renderer compares a text width against is this value scaled by the camera, so it is
        // the proportion that has to hold, not a figure in normalized units.
        #expect(small > 0)
        #expect(abs(large / small - 2) < 0.1)
    }

    @Test func test_clearance_ofAThinBar_followsItsHeightNotItsWidth() {

        // Sixty degrees wide, two tall. Doubling the width must not change the answer: there
        // is no more room for a label than the height allows.
        let wide = clearance(of: [bar(halfWidth: 30, halfHeight: 1)])
        let wider = clearance(of: [bar(halfWidth: 60, halfHeight: 1)])

        #expect(abs(wide - wider) < wide * 0.1)
    }

    @Test func test_clearance_ofAThinBar_isFarSmallerThanItsBoundingBoxSuggests() {

        let result = FlatPathBuilder.build(from: geometry([bar(halfWidth: 30, halfHeight: 1)]),
                                           projectionMode: .plateCarree,
                                           iso2: "xx",
                                           variant: .full)

        // Sixty degrees wide and two tall: the box offers a name half its width to sit in,
        // the land offers a sliver. Measuring the bar against its own box is the comparison
        // that matters - an earlier version of this test compared it to a square's clearance
        // instead, where the two values come out exactly equal and the assertion only passed
        // by rounding.
        let boxHalfWidth = result.labelFitBoundingBox.width / 2

        #expect(result.labelClearance < boxHalfWidth / 10)
    }

    @Test func test_clearance_isNeverNegative() {

        #expect(clearance(of: [square(halfSpan: 10)]) >= 0)
        #expect(clearance(of: [bar(halfWidth: 30, halfHeight: 1)]) >= 0)
    }

    @Test func test_labelFitBoundingBox_omitsThePaddingTheCameraBoxCarries() {

        let result = FlatPathBuilder.build(from: geometry([square(halfSpan: 10)]),
                                           projectionMode: .plateCarree,
                                           iso2: "xx",
                                           variant: .full)

        // The camera's padding is a share of the whole world, so beside a small country it is
        // enormous - it inflated Vatican City's box roughly 200-fold. A name measured against
        // the padded box would be granted room the country does not have, which is why the
        // label pass reads this second, unpadded box.
        #expect(result.labelFitBoundingBox.width < result.focusBoundingBox.width)
        #expect(result.labelFitBoundingBox.height < result.focusBoundingBox.height)

        // Padding is applied to both sides, so each dimension grows by twice its value.
        let widthGrowth = result.focusBoundingBox.width - result.labelFitBoundingBox.width
        #expect(abs(widthGrowth - 0.02) < 0.001)
    }
}
