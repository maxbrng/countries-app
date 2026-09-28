//
//  FlatMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

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

    private(set) var shapes: [RenderCountryShape] = []
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

        do {
            shapes = try await loadShapes(projectionMode, countryIndex.resolverIndex, variant)
            loadState = .ready
        } catch {
            // The shapes are dropped rather than kept half-built: a partial world is harder to
            // recognise as broken than an empty one with a message over it.
            shapes = []
            loadState = .failed
            logger.error("Flat map shapes failed: \(error.localizedDescription, privacy: .public)")
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
