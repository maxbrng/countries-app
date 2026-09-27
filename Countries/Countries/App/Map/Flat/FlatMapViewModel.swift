//
//  FlatMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Observation
import SwiftData

@Observable
@MainActor
final class FlatMapViewModel {

    private(set) var shapes: [RenderCountryShape] = []
    private(set) var countryIndex: CountryIndex = .init(countries: [])

    private(set) var didInitializeCameraForProjection: Bool = false

    private var lastLoadedProjection: FlatMapProjectionMode?
    private var lastLoadedVariant: FlatMapShapeCache.Variant?

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

        do {
            let resolver = countryIndex.resolverIndex
            shapes = try await FlatMapShapeCache.shared.shapes(
                projectionMode: projectionMode,
                resolver: resolver,
                variant: variant
            )
        } catch {
            shapes = []
        }
    }

    func markCameraInitializedForProjection() {
        didInitializeCameraForProjection = true
    }

    func resetCameraInitialization() {
        didInitializeCameraForProjection = false
    }
}
