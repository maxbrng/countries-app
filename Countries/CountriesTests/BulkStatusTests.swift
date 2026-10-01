//
//  BulkStatusTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Covers the bulk write the first launch hands in.
///
/// It is the one place where a single user action changes up to two hundred records, so the
/// failure modes are quiet: a code that matches nothing, a case mismatch against the stored
/// uppercase code, or an empty selection treated as an error rather than as an answer.
@MainActor
struct BulkStatusTests {

    // MARK: - Fixture

    /// A container that lives only for the length of one test.
    private func makeContext() throws -> ModelContext {

        let schema = Schema(versionedSchema: CountriesSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }

    /// Inserts three countries, none of them visited.
    ///
    /// - Parameter context: The context to insert into.
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

    /// The countries currently marked visited, by code.
    private func visitedCodes(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Country>())
            .filter { $0.status == .visited }
            .map(\.iso2))
    }

    // MARK: - Writing

    @Test
    func test_setStatus_forASetOfCodes_marksExactlyThose() throws {

        // Arrange
        let context = try makeContext()
        try makeCountries(in: context)

        // Act
        let changed = try CountryStatusService.setStatus(.visited,
                                                        forCountriesWithISO2: ["DE", "ES"],
                                                        in: context)

        // Assert
        #expect(changed == 2)
        #expect(try visitedCodes(in: context) == ["DE", "ES"])
    }

    @Test
    func test_setStatus_matchesCodesRegardlessOfCase() throws {

        // Arrange
        // The picker hands back what it was given; the store keeps codes uppercase.
        let context = try makeContext()
        try makeCountries(in: context)

        // Act
        try CountryStatusService.setStatus(.visited,
                                           forCountriesWithISO2: ["de", "fR"],
                                           in: context)

        // Assert
        #expect(try visitedCodes(in: context) == ["DE", "FR"])
    }

    // MARK: - Nothing selected

    @Test
    func test_setStatus_withAnEmptySelection_changesNothingAndDoesNotFail() throws {

        // Arrange
        let context = try makeContext()
        try makeCountries(in: context)

        // Act
        let changed = try CountryStatusService.setStatus(.visited,
                                                         forCountriesWithISO2: [],
                                                         in: context)

        // Assert
        // Selecting nothing is a valid answer at first launch, not an error.
        #expect(changed == 0)
        #expect(try visitedCodes(in: context).isEmpty)
    }

    @Test
    func test_setStatus_withACodeThatMatchesNothing_leavesTheRestAlone() throws {

        // Arrange
        let context = try makeContext()
        try makeCountries(in: context)

        // Act
        let changed = try CountryStatusService.setStatus(.visited,
                                                         forCountriesWithISO2: ["DE", "ZZ"],
                                                         in: context)

        // Assert
        #expect(changed == 1)
        #expect(try visitedCodes(in: context) == ["DE"])
    }

    // MARK: - Repeating

    @Test
    func test_setStatus_appliedTwice_reportsNoSecondChange() throws {

        // Arrange
        let context = try makeContext()
        try makeCountries(in: context)
        try CountryStatusService.setStatus(.visited, forCountriesWithISO2: ["DE"], in: context)

        // Act
        let changed = try CountryStatusService.setStatus(.visited,
                                                         forCountriesWithISO2: ["DE"],
                                                         in: context)

        // Assert
        #expect(changed == 0)
        #expect(try visitedCodes(in: context) == ["DE"])
    }

    @Test
    func test_setStatus_doesNotTouchCountriesOutsideTheSelection() throws {

        // Arrange
        let context = try makeContext()
        try makeCountries(in: context)
        let spain = try #require(try context.fetch(FetchDescriptor<Country>())
            .first { $0.iso2 == "ES" })
        try CountryStatusService.setStatus(.wishlist, for: spain, in: context)

        // Act
        try CountryStatusService.setStatus(.visited, forCountriesWithISO2: ["DE"], in: context)

        // Assert
        // A bulk write that quietly cleared everything else would be the worst kind of bug at
        // first launch, because there is nothing to compare against yet.
        #expect(spain.status == .wishlist)
    }
}
