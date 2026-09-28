//
//  FlatMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics
import Observation
import SwiftData

@Observable
@MainActor
final class FlatMapViewModel {

    /// Geometry for the current camera, at the level of detail the screen can resolve.
    private(set) var shapes: [RenderCountryShape] = []

    /// Full geometry, built in the background while the overview is already on screen.
    ///
    /// Empty until that build finishes, which is why ``shapes(forUserZoom:)`` falls back
    /// rather than waiting: a zoom must never block on a build.
    private(set) var detailShapes: [RenderCountryShape] = []

    private(set) var countryIndex: CountryIndex = .init(countries: [])

    private(set) var didInitializeCameraForProjection: Bool = false

    private var lastLoadedProjection: FlatMapProjectionMode?
    private var lastLoadedVariant: FlatMapShapeCache.Variant?

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

    func updateCountryIndex(countries: [Country]) {
        self.countryIndex = CountryIndex(countries: countries)
    }

    func loadShapesIfNeeded(
        projectionMode: FlatMapProjectionMode,
        variant: FlatMapShapeCache.Variant
    ) async {

        if lastLoadedProjection == projectionMode,
           lastLoadedVariant == variant,
           !shapes.isEmpty {
            return
        }

        lastLoadedProjection = projectionMode
        lastLoadedVariant = variant

        let resolver = countryIndex.resolverIndex

        do {
            shapes = try await FlatMapShapeCache.shared.shapes(
                projectionMode: projectionMode,
                resolver: resolver,
                variant: variant
            )
        } catch {
            shapes = []
        }

        // The full geometry is only ever the second step: the overview is on screen within
        // one build, and zooming in before this finishes falls back to it rather than waiting.
        guard variant == .overview else {
            detailShapes = []
            return
        }

        do {
            detailShapes = try await FlatMapShapeCache.shared.shapes(
                projectionMode: projectionMode,
                resolver: resolver,
                variant: .full
            )
        } catch {
            detailShapes = []
        }
    }

    func markCameraInitializedForProjection() {
        didInitializeCameraForProjection = true
    }

    func resetCameraInitialization() {
        didInitializeCameraForProjection = false
    }
}
