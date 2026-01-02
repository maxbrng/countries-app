//
//  CountrySeeder.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//


import Foundation
import SwiftData

@MainActor
struct CountrySeeder {
    enum SeedError: Error { case fileNotFound, decodeFailed }

    static let seedFlagKey = "didSeedCountries_v1"

    static func seedIfNeeded(modelContext: ModelContext) async throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: seedFlagKey) { return }

        guard let url = Bundle.main.url(forResource: "countries", withExtension: "json") else {
            throw SeedError.fileNotFound
        }
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        if let root = try? decoder.decode(CountriesSeed.self, from: data) {
            try await insert(countries: root.countries, modelContext: modelContext)
        } else if let array = try? decoder.decode([CountryDTO].self, from: data) {
            try await insert(countries: array, modelContext: modelContext)
        } else {
            throw SeedError.decodeFailed
        }

        defaults.set(true, forKey: seedFlagKey)
    }

    private static func insert(countries: [CountryDTO], modelContext: ModelContext) async throws {
        for dto in countries {
            let country = Country(iso2: dto.iso2, name: dto.name, continent: dto.continent, status: .none, region: dto.region)
            modelContext.insert(country)
        }
        try modelContext.save()
    }
}
