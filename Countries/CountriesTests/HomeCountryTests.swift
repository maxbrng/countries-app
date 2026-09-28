//
//  HomeCountryTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Covers the one country the user lives in.
///
/// The two rules worth pinning are the ones a reader would assume rather than check: that
/// there can only ever be one, and that it is not counted as an extra visit on top of being a
/// visited country.
@MainActor
struct HomeCountryTests {

    // MARK: - Fixture

    /// A container that lives only for the length of one test.
    private func makeContext() throws -> ModelContext {

        let schema = Schema(versionedSchema: CountriesSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }

    /// Inserts three unvisited countries.
    private func makeCountries(in context: ModelContext) throws {

        for (iso2, name) in [("DE", "Germany"), ("FR", "France"), ("ES", "Spain")] {
            context.insert(Country(iso2: iso2,
                                   nameEnglish: name,
                                   status: .none,
                                   isUNMember: true,
                                   dataHasSourceTranslation: false,
                                   travelTags: [],
                                   climateTags: [],
                                   costLevel: .medium,
                                   safetyLevel: .safe,
                                   translations: [:]))
        }
        try context.save()
    }

    /// Runs `body` with the stored code cleared, and restores it afterwards.
    private func withClearedHome(_ body: () throws -> Void) rethrows {

        let previous = UserDefaults.standard.string(forKey: HomeCountry.storageKey)
        HomeCountry.reset()

        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: HomeCountry.storageKey)
            } else {
                HomeCountry.reset()
            }
        }

        try body()
    }

    /// The visited countries, by code.
    private func visitedCodes(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Country>())
            .filter { $0.status == .visited }
            .map(\.iso2))
    }

    // MARK: - Exactly one

    @Test
    func test_set_storesTheCodeAndMarksItVisited() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)

            // Act
            try HomeCountry.set("DE", in: context)

            // Assert
            #expect(HomeCountry.iso2 == "DE")
            #expect(try visitedCodes(in: context) == ["DE"])
        }
    }

    @Test
    func test_set_twice_replacesTheFirstInsteadOfAddingASecond() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)
            try HomeCountry.set("DE", in: context)

            // Act
            try HomeCountry.set("FR", in: context)

            // Assert
            // Exactly one home country. The previous one stays visited, which is the point of
            // the next test.
            #expect(HomeCountry.iso2 == "FR")
        }
    }

    @Test
    func test_set_lowercased_matchesTheStoredUppercaseCode() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)

            // Act
            try HomeCountry.set("de", in: context)

            // Assert
            #expect(HomeCountry.iso2 == "DE")
            #expect(try visitedCodes(in: context) == ["DE"])
        }
    }

    // MARK: - Not counted twice

    @Test
    func test_set_onAnAlreadyVisitedCountry_doesNotChangeTheVisitedCount() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)
            try CountryStatusService.setStatus(.visited,
                                               forCountriesWithISO2: ["DE", "FR"],
                                               in: context)

            // Act
            try HomeCountry.set("DE", in: context)

            // Assert
            // The home country is a visited country, not a visit on top of one.
            #expect(try visitedCodes(in: context) == ["DE", "FR"])
        }
    }

    @Test
    func test_statistics_countTheHomeCountryOnce() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)

            // Act
            try HomeCountry.set("DE", in: context)
            let countries = try context.fetch(FetchDescriptor<Country>())
            let statistics = DashboardStatistics(countries: countries)

            // Assert
            #expect(statistics.countriesVisited == 1)
            #expect(statistics.countriesTotal == 3)
        }
    }

    // MARK: - Clearing

    @Test
    func test_set_toNil_forgetsTheHomeCountryButKeepsTheVisit() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)
            try HomeCountry.set("DE", in: context)

            // Act
            try HomeCountry.set(nil, in: context)

            // Assert
            // Moving away is not the same as never having been there.
            #expect(HomeCountry.iso2 == nil)
            #expect(try visitedCodes(in: context) == ["DE"])
        }
    }

    @Test
    func test_isHome_identifiesOnlyTheStoredCountry() throws {

        try withClearedHome {
            // Arrange
            let context = try makeContext()
            try makeCountries(in: context)
            try HomeCountry.set("DE", in: context)
            let countries = try context.fetch(FetchDescriptor<Country>())
            let germany = try #require(countries.first { $0.iso2 == "DE" })
            let france = try #require(countries.first { $0.iso2 == "FR" })

            // Act & Assert
            #expect(HomeCountry.isHome(germany))
            #expect(!HomeCountry.isHome(france))
        }
    }
}
