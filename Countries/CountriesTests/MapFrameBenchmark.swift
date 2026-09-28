//
//  MapFrameBenchmark.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Countries

/// Rasterises frames of the real map geometry so tests can put a number on what drawing costs.
///
/// `Canvas` hands its fills and strokes to Core Graphics, so drawing the same paths into a
/// bitmap context measures the same work without needing a running view. Two suites ask
/// different questions of the same harness — `MapPerformanceBudgetTests` whether a frame stays
/// inside the written budget, `FlatMapDrawCostTests` what the coastline casing adds to it — so
/// the drawing itself lives here rather than in either of them.
///
/// - Note: The absolute numbers depend on the machine. See `docs/map-performance-budget.md`
///   for what they are and are not good for.
nonisolated enum MapFrameBenchmark {

    // MARK: - Constants

    /// Side length of the bitmap drawn into, in pixels. Roughly a full-screen map.
    static let canvasSide = 1_200

    /// Frames timed per measurement. Enough to average out scheduling noise, few enough that
    /// a suite using this stays a test and not a benchmark run.
    static let frameCount = 20

    /// Zoom the coastline width is taken at. The world view is the widest thing the map draws.
    static let measuredZoom: CGFloat = 1

    // MARK: - Geometry

    /// Builds the real country geometry for one level of detail.
    ///
    /// - Parameter variant: `.full` for the interactive map, `.light` for the previews.
    /// - Returns: The shapes the renderer would draw.
    /// - Throws: Any error from decoding or building the bundled GeoJSON.
    static func shapes(variant: FlatMapShapeCache.Variant) async throws -> [RenderCountryShape] {

        // Every feature in the bundled file carries a two-letter code, so an empty resolver
        // resolves all of them; the lookup tables only matter for three-letter or name-keyed
        // sources.
        let resolver = GeoJSONLoader.ResolverIndex(iso3ToIso2: [:], nameToIso2: [:])

        return try await FlatMapShapeCache.shared.shapes(projectionMode: .webMercator,
                                                        resolver: resolver,
                                                        variant: variant)
    }

    /// Counts the path elements across every shape.
    ///
    /// - Parameter shapes: Geometry to measure.
    /// - Returns: Total number of path elements, which is what Core Graphics has to walk.
    static func segmentCount(of shapes: [RenderCountryShape]) -> Int {

        var total = 0
        for shape in shapes {
            shape.path.applyWithBlock { _ in total += 1 }
        }

        return total
    }

    // MARK: - Timing

    /// Draws ``frameCount`` frames and returns the average wall time of one.
    ///
    /// - Parameters:
    ///   - shapes: Geometry to draw.
    ///   - drawsCoastline: Whether the casing pass is included. Defaults to `true`, which is
    ///     what the app draws.
    /// - Returns: Average milliseconds per frame, or `nan` when no context could be created.
    static func millisecondsPerFrame(drawing shapes: [RenderCountryShape],
                                     drawsCoastline: Bool = true) -> Double {

        guard let context = CGContext(data: nil,
                                      width: canvasSide,
                                      height: canvasSide,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            Issue.record("Could not create the bitmap context to draw into")
            return .nan
        }

        let worldSide = CGFloat(canvasSide)
        let scaled = shapes.map { shape -> CGPath in
            var transform = CGAffineTransform(scaleX: worldSide, y: worldSide)
            return shape.path.copy(using: &transform) ?? shape.path
        }

        // One untimed frame so the first-touch cost of the paths does not land in the average.
        drawFrame(scaled, in: context, drawsCoastline: drawsCoastline)

        let start = Date.now
        for _ in 0..<frameCount {
            drawFrame(scaled, in: context, drawsCoastline: drawsCoastline)
        }
        let elapsed = Date.now.timeIntervalSince(start)

        return elapsed / Double(frameCount) * 1_000
    }

    /// Draws one frame: the optional casing pass, then a fill and an interior border per country.
    private static func drawFrame(_ paths: [CGPath],
                                  in context: CGContext,
                                  drawsCoastline: Bool) {

        if drawsCoastline {
            context.setLineWidth(MapStrokeMetrics.coastlineWidth(forUserZoom: measuredZoom))
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
}
