//
//  MapPerformanceBudgetTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import Testing
@testable import Countries

/// Holds the map to the budget written down in `docs/map-performance-budget.md`.
///
/// Two things are checked, and they guard different failures. The frame measurements catch work
/// that was added to the draw pass; the resolution tests catch a call site quietly asking for
/// full-detail geometry it does not need. The second is the cheaper failure to introduce and the
/// harder one to notice, which is why it is a test rather than a comment.
struct MapPerformanceBudgetTests {

    // MARK: - Constants

    /// Highest share of the full geometry's path segments the light variant may carry.
    ///
    /// Simplification is what the preview budget is bought with; this is the assertion that the
    /// purchase actually happened.
    private static let previewSegmentShare: Double = 0.5

    // MARK: - Detail resolution

    @Test func test_variant_forThePreviewPreset_isLight() {

        // Arrange / Act / Assert: the preset the dashboard and onboarding name.
        #expect(MapDetailRequest.preview.variant == .light)
    }

    @Test func test_variant_forTheInteractivePreset_isFull() {

        #expect(MapDetailRequest.interactive.variant == .full)
    }

    @Test func test_variant_withAnySwitchOn_isFull() {

        // Arrange: each switch on its own, the other two off.
        let withSelection = MapDetailRequest(selectionEnabled: true,
                                             interactiveEnabled: false,
                                             labelsEnabled: false)
        let withInteraction = MapDetailRequest(selectionEnabled: false,
                                               interactiveEnabled: true,
                                               labelsEnabled: false)
        let withLabels = MapDetailRequest(selectionEnabled: false,
                                          interactiveEnabled: false,
                                          labelsEnabled: true)

        // Act / Assert: nothing that can be touched or read is drawn from light geometry.
        #expect(withSelection.variant == .full)
        #expect(withInteraction.variant == .full)
        #expect(withLabels.variant == .full)
    }

    @Test func test_previewPreset_leavesEverySwitchOff() {

        // The preview budget rests entirely on this. A ticket that turns one of them on has to
        // change this test, which is the point at which somebody reads the budget.
        #expect(!MapDetailRequest.preview.selectionEnabled)
        #expect(!MapDetailRequest.preview.interactiveEnabled)
        #expect(!MapDetailRequest.preview.labelsEnabled)
    }

    // MARK: - Geometry

    @Test func test_lightGeometry_carriesFarFewerSegmentsThanFull() async throws {

        // Arrange
        let full = try await MapFrameBenchmark.shapes(variant: .full)
        let light = try await MapFrameBenchmark.shapes(variant: .light)

        // Act
        let fullSegments = MapFrameBenchmark.segmentCount(of: full)
        let lightSegments = MapFrameBenchmark.segmentCount(of: light)

        // Assert: the preview is cheap because it is simplified, not because it leaves parts of
        // the world out. Every country is still there.
        #expect(!full.isEmpty)
        #expect(light.count == full.count)
        #expect(Double(lightSegments) < Double(fullSegments) * Self.previewSegmentShare)
    }

    // MARK: - Frame budget

    @Test func test_frameCost_staysWithinTheWrittenBudget() async throws {

        for variant in [FlatMapShapeCache.Variant.full, .light] {

            // Arrange
            let geometry = try await MapFrameBenchmark.shapes(variant: variant)
            #expect(!geometry.isEmpty)

            // Act
            let measured = MapFrameBenchmark.millisecondsPerFrame(drawing: geometry)

            // Assert
            let budget = MapPerformanceBudget.frameMilliseconds(for: variant)
            print("MAPBUDGET \(variant) measured=\(measured)ms budget=\(budget)ms")
            #expect(measured < budget)
        }
    }

    @Test func test_previewFrame_costsAFractionOfAFullOne() async throws {

        // Arrange
        let full = try await MapFrameBenchmark.shapes(variant: .full)
        let light = try await MapFrameBenchmark.shapes(variant: .light)

        // Act
        let fullCost = MapFrameBenchmark.millisecondsPerFrame(drawing: full)
        let previewCost = MapFrameBenchmark.millisecondsPerFrame(drawing: light)

        // Assert
        let share = previewCost / fullCost
        print("MAPBUDGET share measured=\(share) budget=\(MapPerformanceBudget.previewCostShare)")
        #expect(share < MapPerformanceBudget.previewCostShare)
    }
}
