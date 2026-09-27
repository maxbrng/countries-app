//
//  FlatMapCameraTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import Testing
@testable import Countries

/// Covers the clamping that keeps the map from being panned or zoomed out of its own world.
///
/// The fixture is a square world laid out in a portrait viewport, the shape the flat map
/// actually has on a phone: 402 x 402 points of world inside a 402 x 874 point viewport, so
/// `fitScale` is 874 / 402.
struct FlatMapCameraTests {

    // MARK: - Fixture

    private let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let worldRect = CGRect(x: 0, y: 0, width: 402, height: 402)
    private var fitScale: CGFloat { 874.0 / 402.0 }

    // MARK: - Zoom

    @Test func test_clamp_zoomBelowTheMinimum_isRaisedToIt() {

        var camera = FlatMapCamera()
        camera.userZoom = 0.01

        camera.clamp(viewport: viewport, worldRect: worldRect, fitScale: fitScale)

        let minimum = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)
        #expect(camera.userZoom == minimum)
    }

    @Test func test_clamp_zoomAboveTheMaximum_isLoweredToIt() {

        var camera = FlatMapCamera()
        camera.userZoom = 10_000

        camera.clamp(viewport: viewport, worldRect: worldRect, fitScale: fitScale)

        #expect(camera.userZoom == camera.maxUserZoom)
    }

    @Test func test_minimumUserZoom_fillsTheViewport() {

        let camera = FlatMapCamera()

        let minimum = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)

        // At the minimum the world must still cover the viewport on both axes, otherwise
        // the map has a visible edge.
        let totalScale = fitScale * minimum
        #expect(worldRect.width * totalScale >= viewport.width - 1e-6)
        #expect(worldRect.height * totalScale >= viewport.height - 1e-6)
    }

    @Test func test_minimumUserZoom_degenerateViewport_returnsOne() {

        let camera = FlatMapCamera()

        #expect(camera.minimumUserZoom(viewport: .zero,
                                       worldRect: worldRect,
                                       fitScale: fitScale) == 1)
        #expect(camera.minimumUserZoom(viewport: viewport,
                                       worldRect: .zero,
                                       fitScale: fitScale) == 1)
        #expect(camera.minimumUserZoom(viewport: viewport,
                                       worldRect: worldRect,
                                       fitScale: 0) == 1)
    }

    // MARK: - Centre

    @Test func test_clampCenter_offTheWesternEdge_isPulledBackIn() {

        let camera = FlatMapCamera()
        let totalScale = fitScale * 4

        let clamped = camera.clampCenter(CGPoint(x: -5, y: 0.5),
                                         viewport: viewport,
                                         worldRect: worldRect,
                                         totalScale: totalScale)

        let halfVisibleWidth = (viewport.width / totalScale) / worldRect.width * 0.5
        #expect(abs(clamped.x - halfVisibleWidth) < 1e-9)
    }

    @Test func test_clampCenter_offTheNorthernEdge_isPulledBackIn() {

        let camera = FlatMapCamera()
        let totalScale = fitScale * 4

        let clamped = camera.clampCenter(CGPoint(x: 0.5, y: -3),
                                         viewport: viewport,
                                         worldRect: worldRect,
                                         totalScale: totalScale)

        let halfVisibleHeight = (viewport.height / totalScale) / worldRect.height * 0.5
        #expect(abs(clamped.y - halfVisibleHeight) < 1e-9)
    }

    @Test func test_clampCenter_wrappingHorizontally_wrapsInsteadOfClamping() {

        var camera = FlatMapCamera()
        camera.wrapsHorizontally = true

        let clamped = camera.clampCenter(CGPoint(x: 1.25, y: 0.5),
                                         viewport: viewport,
                                         worldRect: worldRect,
                                         totalScale: fitScale * 4)

        #expect(abs(clamped.x - 0.25) < 1e-9)
    }

    @Test func test_clampCenter_wrappingHorizontally_negativeValueWrapsForwards() {

        var camera = FlatMapCamera()
        camera.wrapsHorizontally = true

        let clamped = camera.clampCenter(CGPoint(x: -0.25, y: 0.5),
                                         viewport: viewport,
                                         worldRect: worldRect,
                                         totalScale: fitScale * 4)

        #expect(abs(clamped.x - 0.75) < 1e-9)
    }

    @Test func test_clampCenter_degenerateInput_returnsTheCentreUnchanged() {

        let camera = FlatMapCamera()
        let centre = CGPoint(x: 42, y: -7)

        let clamped = camera.clampCenter(centre,
                                         viewport: viewport,
                                         worldRect: worldRect,
                                         totalScale: 0)

        #expect(clamped == centre)
    }
}
