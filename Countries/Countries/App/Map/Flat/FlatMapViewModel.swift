//
//  FlatMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class FlatMapViewModel {
    
    private(set) var shapes: [RenderCountryShape] = []
    private(set) var countryIndex: CountryIndex = .init(countries: [])

    private(set) var didInitializeCameraForProjection: Bool = false

    func updateCountryIndex(countries: [Country]) {
        self.countryIndex = CountryIndex(countries: countries)
    }

    func loadShapesIfNeeded(projectionMode: FlatMapProjectionMode) async {
        
        do {
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(index: countryIndex, keySet: .init())
            
            let builtShapes = resolved.compactMap { feature -> RenderCountryShape? in
                
                let built = FlatPathBuilder.build(from: feature.geometry, projectionMode: projectionMode, iso2: feature.iso2)
                
                return RenderCountryShape(
                    id: feature.iso2,
                    iso2: feature.iso2,
                    path: built.path,
                    labelAnchor: built.labelAnchor,
                    focusBoundingBoxNormalized: built.focusBoundingBox
                )
            }
            self.shapes = builtShapes
        } catch {
            // Keep behavior: fail silently but clear shapes.
            self.shapes = []
        }
    }

    func markCameraInitializedForProjection() {
        didInitializeCameraForProjection = true
    }

    func resetCameraInitialization() {
        didInitializeCameraForProjection = false
    }
}
