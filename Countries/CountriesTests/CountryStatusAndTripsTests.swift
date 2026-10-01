//
//  CountryStatusAndTripsTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Covers the rule that a country's status and the trips that mention it are separate records.
///
/// Setting a country back to "not visited" is not a statement that the journey never happened,
/// and deleting a trip is not a statement that the country was never seen. Both directions are
/// easy to break by accident with a cascade rule or a well-meant cleanup, and neither would
/// show up in the UI until a user lost data, so both are pinned here.
@MainActor
struct CountryStatusAndTripsTests {

    // MARK: - Fixture

    /// A container that lives only for the length of one test.
    private func makeContext() throws -> ModelContext {

        let schema = Schema([Country.self, Trip.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)

        return ModelContext(container)
    }

    /// Builds a country with only the fields these tests care about filled in.
    ///
    /// - Parameters:
    ///   - iso2: The country code.
    ///   - name: The English name.
    ///   - status: The tracking status to start from.
    private func makeCountry(iso2: String,
                             name: String,
                             status: CountryStatus) -> Country {

        Country(iso2: iso2,
                nameEnglish: name,
                status: status,
                isUNMember: true,
                dataHasSourceTranslation: false,
                travelTags: [],
                climateTags: [],
                costLevel: .medium,
                safetyLevel: .safe,
                translations: [:])
    }

    /// Inserts one visited country that belongs to one trip.
    ///
    /// - Parameter context: The context to insert into.
    /// - Returns: The country and the trip, both already saved.
    private func makeVisitedCountryOnATrip(in context: ModelContext) throws -> (Country, Trip) {

        let country = makeCountry(iso2: "FR", name: "France", status: .visited)
        context.insert(country)

        let trip = Trip()
        trip.title = "Summer"
        trip.countries = [country]
        context.insert(trip)

        try context.save()

        return (country, trip)
    }

    // MARK: - Withdrawing the status

    @Test func test_setStatus_withdrawingVisited_leavesTheTripInPlace() throws {

        // Arrange
        let context = try makeContext()
        let (country, trip) = try makeVisitedCountryOnATrip(in: context)

        // Act
        try CountryStatusService.setStatus(.none, for: country, in: context)

        // Assert
        let remaining = try context.fetch(FetchDescriptor<Trip>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.persistentModelID == trip.persistentModelID)
        #expect(trip.countries.count == 1)
        #expect(country.status == CountryStatus.none)
    }

    @Test func test_toggleStatus_withdrawingVisited_leavesTheTripInPlace() throws {

        let context = try makeContext()
        let (country, _) = try makeVisitedCountryOnATrip(in: context)

        try CountryStatusService.toggleStatus(.visited, for: country, in: context)

        #expect(country.status == CountryStatus.none)
        #expect(try context.fetch(FetchDescriptor<Trip>()).count == 1)
    }

    // MARK: - Deleting the trip

    @Test func test_deletingATrip_leavesTheCountryStatusUntouched() throws {

        let context = try makeContext()
        let (country, trip) = try makeVisitedCountryOnATrip(in: context)

        context.delete(trip)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Country>()).count == 1)
        #expect(country.status == .visited)
    }

    // MARK: - When to warn

}
