//
//  FlatMapDrawCostTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Countries

/// Measures what one frame of the flat map costs to rasterise, with and without the coastline
/// casing added in [D-01].
///
/// `Canvas` hands its fills and strokes to Core Graphics, so drawing the same paths into a
/// bitmap context measures the same work without needing a running view. The absolute numbers
/// depend on the machine; what the ticket needs, and what the assertion guards, is the *ratio*
/// between a frame with the casing and one without.
@MainActor
struct FlatMapDrawCostTests {

    // MARK: - Constants

    /// Side length of the bitmap drawn into, in pixels. Roughly a full-screen map.
    private static let canvasSide = 1_200

    /// Frames timed per measurement. Enough to average out scheduling noise, few enough that
    /// the suite stays a test and not a benchmark run.
    private static let frameCount = 20

    /// Highest acceptable cost of the casing, as a multiple of a frame without it.
    ///
    /// Measured at 1.31 with the shipped widths. The ceiling sits just above that, because the
    /// number it really guards is ``MapStrokeMetrics/coastlineMaximumWidth``: one tenth of a
    /// point over it and Core Graphics stops rasterising the stroke as a hairline, which costs
    /// a factor of thirteen rather than a third. This test is what makes that cliff visible
    /// instead of letting it reach a device.
    private static let costCeiling = 1.45

    // MARK: - Geometry

    /// Builds the real country geometry for one level of detail.
    ///
    /// - Parameter variant: `.full` for the interactive map, `.light` for the dashboard preview.
    /// - Returns: The shapes the renderer would draw.
    private func shapes(variant: FlatMapShapeCache.Variant) async throws -> [RenderCountryShape] {

        // Every feature in the bundled file carries a two-letter code, so an empty resolver
        // resolves all of them; the lookup tables only matter for three-letter or name-keyed
        // sources.
        let resolver = GeoJSONLoader.ResolverIndex(iso3ToIso2: [:], nameToIso2: [:])

        return try await FlatMapShapeCache.shared.shapes(projectionMode: .webMercator,
                                                         resolver: resolver,
                                                         variant: variant)
    }

    // MARK: - Timing

    /// Draws `frameCount` frames and returns the average wall time of one, in milliseconds.
    ///
    /// - Parameters:
    ///   - shapes: Geometry to draw.
    ///   - drawsCoastline: Whether the casing pass is included.
    /// - Returns: Average milliseconds per frame.
    private func millisecondsPerFrame(drawing shapes: [RenderCountryShape],
                                      drawsCoastline: Bool) throws -> Double {

        let side = Self.canvasSide
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: nil,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            Issue.record("Could not create the bitmap context to draw into")
            return .nan
        }

        let worldRect = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
        let scaled = shapes.map { shape -> CGPath in
            var transform = CGAffineTransform(scaleX: worldRect.width, y: worldRect.height)
            return shape.path.copy(using: &transform) ?? shape.path
        }

        // One untimed frame so the first-touch costs of the paths do not land in the average.
        drawFrame(scaled, in: context, drawsCoastline: drawsCoastline)

        let start = Date.now
        for _ in 0..<Self.frameCount {
            drawFrame(scaled, in: context, drawsCoastline: drawsCoastline)
        }
        let elapsed = Date.now.timeIntervalSince(start)

        return elapsed / Double(Self.frameCount) * 1_000
    }

    /// Draws one frame: the optional casing pass, then a fill and a hairline per country.
    private func drawFrame(_ paths: [CGPath],
                           in context: CGContext,
                           drawsCoastline: Bool) {

        if drawsCoastline {
            context.setLineWidth(MapStrokeMetrics.coastlineWidth(forUserZoom: 1))
            context.setStrokeColor(gray: 0.55, alpha: 1)
            for path in paths {
                context.addPath(path)
                context.strokePath()
            }
        }

        for path in paths {
            context.addPath(path)
            context.setFillColor(gray: 0.78, alpha: 1)
            context.fillPath(using: .evenOdd)

            context.addPath(path)
            context.setLineWidth(MapStrokeMetrics.interiorBorderWidth)
            context.setStrokeColor(gray: 1, alpha: 0.75)
            context.strokePath()
        }
    }

    // MARK: - Tests

    @Test func test_coastlineWidth_staysOnTheHairlineFastPath() {

        // Arrange / Act / Assert: no zoom may ever push the stroke past the cliff.
        for zoom in [CGFloat(0.5), 1, 2, 4, 16, 64, 1_000] {
            #expect(MapStrokeMetrics.coastlineWidth(forUserZoom: zoom)
                    <= MapStrokeMetrics.coastlineMaximumWidth)
        }
    }

    @Test func test_coastlineWidth_growsWithTheZoomAndThenStops() {

        let atWorldView = MapStrokeMetrics.coastlineWidth(forUserZoom: 1)
        let zoomedIn = MapStrokeMetrics.coastlineWidth(forUserZoom: 3)
        let farIn = MapStrokeMetrics.coastlineWidth(forUserZoom: 40)

        #expect(atWorldView == MapStrokeMetrics.coastlineMinimumWidth)
        #expect(zoomedIn > atWorldView)
        #expect(farIn == MapStrokeMetrics.coastlineMaximumWidth)
    }

    @Test func test_drawCost_coastlineCasing_staysWithinItsBudget() async throws {

        for variant in [FlatMapShapeCache.Variant.full, .light] {

            // Arrange
            let geometry = try await shapes(variant: variant)
            #expect(!geometry.isEmpty)

            // Act
            let without = try millisecondsPerFrame(drawing: geometry, drawsCoastline: false)
            let with = try millisecondsPerFrame(drawing: geometry, drawsCoastline: true)

            // Assert
            let factor = with / without
            print("DRAWCOST \(variant) without=\(without)ms with=\(with)ms factor=\(factor)")
            #expect(factor < Self.costCeiling)
        }
    }
}
