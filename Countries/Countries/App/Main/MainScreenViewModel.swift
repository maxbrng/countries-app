//
//  MainScreenViewModel.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import Combine

@MainActor
final class MainScreenViewModel: ObservableObject {

    @Published var countriesVisited: Double = 0
    @Published var continentsVisited: Double = 0
    @Published var totalCountries: Double = 0
    @Published var totalContinents: Double = 0
    @Published var visitedCountries: [Country] = []
    @Published var wishlistCountries: [Country] = []

    func update(from allCountries: [Country]) {
        
        totalCountries = Double(allCountries.count)

        visitedCountries = allCountries
            .filter { $0.status == .visited }
            .sortedByDisplayName()

        wishlistCountries = allCountries
            .filter { $0.status == .wishlist }
            .sortedByDisplayName()

        countriesVisited = Double(visitedCountries.count)

        let allContinents = Set(allCountries.compactMap(\.continent))
        totalContinents = Double(allContinents.count)

        let visitedContinents = Set(visitedCountries.compactMap(\.continent))
        continentsVisited = Double(visitedContinents.count)
    }
}
