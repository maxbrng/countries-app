//
//  MapLoadStateTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Countries

/// Covers what the two maps report while their geometry is being built, and after it fails.
///
/// The failure branch is the one that matters: before this, a failed build left the flat map as
/// an empty ocean with no spinner, no message and no way to try again, which is
/// indistinguishable from a world where nothing has been visited.
@MainActor
struct MapLoadStateTests {

    // MARK: - Fixture

    /// An error that stands for any failure inside the shape builder.
    private struct BuildFailure: Error {}

    /// One shape, so a successful load produces a non-empty result.
    private static let oneShape = RenderCountryShape(id: "de",
                                                     iso2: "de",
                                                     path: CGMutablePath(),
                                                     labelAnchor: .zero,
                                                     focusBoundingBoxNormalized: .zero,
                                                     labelFitBoundingBoxNormalized: .zero,
                                                     boundsNormalized: .zero,
                                                     labelInfo: .unknown)

    // MARK: - Flat map

    @Test
    func test_loadState_beforeLoading_isIdle() {

        // Arrange & Act
        let viewModel = FlatMapViewModel { _, _, _ in [] }

        // Assert
        #expect(viewModel.loadState == .idle)
    }

    @Test
    func test_loadShapesIfNeeded_whenTheBuilderThrows_reportsFailureAndDropsTheShapes() async {

        // Arrange
        let viewModel = FlatMapViewModel { _, _, _ in throw BuildFailure() }

        // Act
        await viewModel.loadShapesIfNeeded(projectionMode: .webMercator, variant: .full)

        // Assert
        #expect(viewModel.loadState == .failed)
        #expect(viewModel.shapes.isEmpty)
    }

    @Test
    func test_reloadShapes_afterAFailure_canSucceed() async {

        // Arrange
        // Fails once, then succeeds — exactly what the retry button is for.
        let attempts = Attempts()
        let viewModel = FlatMapViewModel { _, _, _ in
            guard await attempts.recordAndCheckWhetherFirst() else { return [Self.oneShape] }
            throw BuildFailure()
        }

        // Act
        await viewModel.loadShapesIfNeeded(projectionMode: .webMercator, variant: .full)
        let afterFailure = viewModel.loadState
        await viewModel.reloadShapes(projectionMode: .webMercator, variant: .full)

        // Assert
        #expect(afterFailure == .failed)
        #expect(viewModel.loadState == .ready)
        #expect(await attempts.count == 2)
    }

    @Test
    func test_loadShapesIfNeeded_calledTwiceForTheSameRequest_buildsOnlyOnce() async {

        // Arrange
        let attempts = Attempts()
        let viewModel = FlatMapViewModel { _, _, _ in
            _ = await attempts.recordAndCheckWhetherFirst()
            return [Self.oneShape]
        }

        // Act
        await viewModel.loadShapesIfNeeded(projectionMode: .webMercator, variant: .full)
        await viewModel.loadShapesIfNeeded(projectionMode: .webMercator, variant: .full)

        // Assert
        #expect(viewModel.loadState == .ready)
        #expect(await attempts.count == 1)
    }

    // MARK: - Globe

    @Test
    func test_globeLoadState_whenTheBuilderThrows_reportsFailure() async {

        // Arrange
        let viewModel = GlobeMapViewModel { _ in throw BuildFailure() }

        // Act
        await viewModel.loadShapesIfNeeded()

        // Assert
        #expect(viewModel.loadState == .failed)
        #expect(viewModel.shapes.isEmpty)
    }

    @Test
    func test_globeReloadShapes_afterAFailure_canSucceed() async {

        // Arrange
        let attempts = Attempts()
        let viewModel = GlobeMapViewModel { _ in
            guard await attempts.recordAndCheckWhetherFirst() else { return [] }
            throw BuildFailure()
        }

        // Act
        await viewModel.loadShapesIfNeeded()
        await viewModel.reloadShapes()

        // Assert
        #expect(viewModel.loadState == .ready)
        #expect(await attempts.count == 2)
    }
}

/// Counts how often an injected loader ran, from whatever task it runs on.
private actor Attempts {

    /// Number of calls so far.
    private(set) var count = 0

    /// Records one call.
    ///
    /// - Returns: `true` if this was the first call.
    func recordAndCheckWhetherFirst() -> Bool {

        count += 1

        return count == 1
    }
}
