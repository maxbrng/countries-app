//
//  FlatMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics
import Foundation
import Observation
import os
import SwiftData

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "FlatMap")

/// Holds the geometry the flat map draws, and the state of loading it.
@Observable
@MainActor
final class FlatMapViewModel {

    // MARK: - Nested types

    /// Builds the shapes for one projection and variant.
    ///
    /// Injectable so the failure branch can be exercised; the default goes through
    /// ``FlatMapShapeCache``.
    typealias ShapeLoader = @Sendable (
        FlatMapProjectionMode,
        GeoJSONLoader.ResolverIndex,
        FlatMapShapeCache.Variant
    ) async throws -> [RenderCountryShape]

    // MARK: - State

    /// Geometry for the current camera, at the level of detail the screen can resolve.
    private(set) var shapes: [RenderCountryShape] = []

    /// Full geometry, built in the background while the overview is already on screen.
    ///
    /// Empty until that build finishes, which is why ``shapes(forUserZoom:)`` falls back
    /// rather than waiting: a zoom must never block on a build.
    private(set) var detailShapes: [RenderCountryShape] = []

    private(set) var countryIndex: CountryIndex = .init(countries: [])

    /// Where the geometry stands, driving ``LoadStateOverlay``.
    private(set) var loadState: LoadState = .idle

    private(set) var didInitializeCameraForProjection: Bool = false

    private var lastLoadedProjection: FlatMapProjectionMode?
    private var lastLoadedVariant: FlatMapShapeCache.Variant?

    private let loadShapes: ShapeLoader

    // MARK: - Life cycle

    /// - Parameter loadShapes: How the geometry is built. Defaults to the shared cache.
    init(loadShapes: @escaping ShapeLoader = { projection, resolver, variant in
        try await FlatMapShapeCache.shared.shapes(projectionMode: projection,
                                                  resolver: resolver,
                                                  variant: variant)
    }) {
        self.loadShapes = loadShapes
    }

    // MARK: - Level of detail

    /// User zoom at which the full geometry starts to be worth its cost.
    ///
    /// The overview is simplified to half a point at a world view about 1200 points wide, so
    /// at twice that scale its dropped vertices would begin to land on separate pixels. That
    /// is the first zoom level at which the finer geometry can be seen at all.
    static let detailZoomThreshold: CGFloat = 2

    /// The geometry to draw and hit-test at this zoom.
    ///
    /// - Parameter userZoom: The user's zoom factor on top of the fit scale.
    /// - Returns: The full geometry past ``detailZoomThreshold`` once it has been built, the
    ///   overview otherwise.
    func shapes(forUserZoom userZoom: CGFloat) -> [RenderCountryShape] {

        guard userZoom >= Self.detailZoomThreshold, !detailShapes.isEmpty else { return shapes }

        return detailShapes
    }

    // MARK: - Loading

    func updateCountryIndex(countries: [Country]) {
        self.countryIndex = CountryIndex(countries: countries)
    }

    /// Loads the geometry unless the same request already succeeded.
    ///
    /// - Parameters:
    ///   - projectionMode: Projection the shapes are built in.
    ///   - variant: Detail level to build.
    func loadShapesIfNeeded(
        projectionMode: FlatMapProjectionMode,
        variant: FlatMapShapeCache.Variant
    ) async {

        if lastLoadedProjection == projectionMode,
           lastLoadedVariant == variant,
           !shapes.isEmpty {
            loadState = .ready
            return
        }

        lastLoadedProjection = projectionMode
        lastLoadedVariant = variant
        loadState = .loading

        let resolver = countryIndex.resolverIndex

        do {
            shapes = try await loadShapes(projectionMode, resolver, variant)
            loadState = .ready
        } catch {
            // The shapes are dropped rather than kept half-built: a partial world is harder to
            // recognise as broken than an empty one with a message over it.
            shapes = []
            loadState = .failed
            logger.error("Flat map shapes failed: \(error.localizedDescription, privacy: .public)")
        }

        // The full geometry is only ever the second step: the overview is on screen within
        // one build, and zooming in before this finishes falls back to it rather than waiting.
        guard variant == .overview else {
            detailShapes = []
            return
        }

        do {
            detailShapes = try await loadShapes(projectionMode, resolver, .full)
        } catch {
            detailShapes = []
        }
    }

    /// Runs the load again after a failure, ignoring the memo.
    ///
    /// - Parameters:
    ///   - projectionMode: Projection the shapes are built in.
    ///   - variant: Detail level to build.
    func reloadShapes(
        projectionMode: FlatMapProjectionMode,
        variant: FlatMapShapeCache.Variant
    ) async {

        lastLoadedProjection = nil
        lastLoadedVariant = nil

        await loadShapesIfNeeded(projectionMode: projectionMode, variant: variant)
    }

    func markCameraInitializedForProjection() {
        didInitializeCameraForProjection = true
    }

    func resetCameraInitialization() {
        didInitializeCameraForProjection = false
    }
}
