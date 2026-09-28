//
//  FlatMapDrawCostTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import Testing
@testable import Countries

/// Measures what the coastline casing added in [D-01] costs, as a share of a frame without it.
///
/// The absolute numbers depend on the machine, so what the ticket needed, and what the assertion
/// guards, is the *ratio* between a frame with the casing and one without.
/// ``MapFrameBenchmark`` does the drawing; `MapPerformanceBudgetTests` asks the same harness the
/// other question, which is whether a whole frame stays inside its budget.
struct FlatMapDrawCostTests {

    // MARK: - Constants

    /// Highest acceptable cost of the casing, as a multiple of a frame without it.
    ///
    /// Measured at 1.26-1.33 with the shipped widths. The ceiling sits just above that, because
    /// the number it really guards is ``MapStrokeMetrics/coastlineMaximumWidth``: one tenth of a
    /// point over it and Core Graphics stops rasterising the stroke as a hairline, which costs
    /// a factor of thirteen rather than a third. This test is what makes that cliff visible
    /// instead of letting it reach a device.
    private static let costCeiling = 1.45

    // MARK: - Tests

    @Test func test_coastlineWidth_staysOnTheHairlineFastPath() {

        // Arrange / Act / Assert: no zoom may ever push the stroke past the cliff.
        for zoom in [CGFloat(0.5), 1, 2, 4, 16, 64, 1_000] {
            #expect(MapStrokeMetrics.coastlineWidth(forUserZoom: zoom)
                    <= MapStrokeMetrics.coastlineMaximumWidth)
        }
    }

    @Test func test_coastlineWidth_growsWithTheZoomAndThenStops() {

        // Arrange / Act
        let atWorldView = MapStrokeMetrics.coastlineWidth(forUserZoom: 1)
        let zoomedIn = MapStrokeMetrics.coastlineWidth(forUserZoom: 3)
        let farIn = MapStrokeMetrics.coastlineWidth(forUserZoom: 40)

        // Assert
        #expect(atWorldView == MapStrokeMetrics.coastlineMinimumWidth)
        #expect(zoomedIn > atWorldView)
        #expect(farIn == MapStrokeMetrics.coastlineMaximumWidth)
    }

    @Test func test_drawCost_coastlineCasing_staysWithinItsBudget() async throws {

        for variant in [FlatMapShapeCache.Variant.full, .light] {

            // Arrange
            let geometry = try await MapFrameBenchmark.shapes(variant: variant)
            #expect(!geometry.isEmpty)

            // Act
            let without = MapFrameBenchmark.millisecondsPerFrame(drawing: geometry,
                                                                 drawsCoastline: false)
            let with = MapFrameBenchmark.millisecondsPerFrame(drawing: geometry,
                                                              drawsCoastline: true)

            // Assert
            let factor = with / without
            print("DRAWCOST \(variant) without=\(without)ms with=\(with)ms factor=\(factor)")
            #expect(factor < Self.costCeiling)
        }
    }
}
