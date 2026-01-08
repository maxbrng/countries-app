//
//  GlobeMapViewModel.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class GlobeMapViewModel {
    
    private(set) var shapes: [GlobeCountryShape] = []
    private(set) var countryIndex: CountryIndex = .init(countries: [])
    
    var isLoading: Bool = true

    func updateCountryIndex(countries: [Country]) {
        self.countryIndex = CountryIndex(countries: countries)
    }

    func loadShapes() async {
        isLoading = true
        do {
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(index: countryIndex, keySet: .init())
            self.shapes = GlobeShapeBuilder.buildShapes(from: resolved)
        } catch {
            self.shapes = []
        }
        isLoading = false
    }
}
