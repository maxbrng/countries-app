//
//  TripDeletionTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Covers the promise the delete confirmation makes: it names both sides correctly, and the
/// undo within the window puts the trip back with everything on it.
///
/// A restore that silently dropped the notes or half the countries would look like a success
/// on screen — the trip is back in the list — and only be noticed much later, so each part of
/// the snapshot is checked individually rather than through the row.
@MainActor
struct TripDeletionTests {

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
    private func makeCountry(iso2: String, name: String) -> Country {

        Country(iso2: iso2,
                nameEnglish: name,
                status: .visited,
                isUNMember: true,
                dataHasSourceTranslation: false,
                travelTags: [],
                climateTags: [],
                costLevel: .medium,
                safetyLevel: .safe,
                translations: [:])
    }

    /// Inserts a fully populated trip across two countries.
    ///
    /// - Parameter context: The context to insert into.
    /// - Returns: The saved trip.
    private func makeFullTrip(in context: ModelContext) throws -> Trip {

        let portugal = makeCountry(iso2: "PT", name: "Portugal")
        let spain = makeCountry(iso2: "ES", name: "Spain")
        context.insert(portugal)
        context.insert(spain)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(title: "Iberia",
                        startDate: start,
                        endDate: start.addingTimeInterval(60 * 60 * 24 * 6),
                        countries: [spain, portugal],
                        notes: "Train from Lisbon to Madrid.")

        context.insert(trip)
        try context.save()

        return trip
    }

    // MARK: - Summary

    @Test
    func test_summary_forFullTrip_listsBothSidesOfTheDeletion() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)

        // Act
        let summary = TripDeletion.summary(for: trip)

        // Assert
        #expect(summary.tripTitle == "Iberia")
        #expect(summary.dateRange != nil)
        #expect(summary.hasNotes)
        #expect(summary.countryNames == ["Portugal", "Spain"])
    }

    @Test
    func test_summary_forTripWithBlankNotes_reportsNoNotes() throws {

        // Arrange
        let context = try makeContext()
        let trip = Trip(title: "Empty", notes: "   ")
        context.insert(trip)

        // Act
        let summary = TripDeletion.summary(for: trip)

        // Assert
        #expect(!summary.hasNotes)
        #expect(summary.countryNames.isEmpty)
    }

    // MARK: - Deletion

    @Test
    func test_delete_removesTheTripButKeepsItsCountries() throws {

        // Arrange
        let context = try makeContext()
        _ = try makeFullTrip(in: context)

        // Act
        let trip = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
        TripDeletion.delete(trip, in: context)

        // Assert
        #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Country>()).count == 2)
    }

    // MARK: - Restore

    @Test
    func test_restore_afterDeletion_bringsBackEveryFieldAndCountry() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)
        let expectedTitle = trip.title
        let expectedStart = trip.startDate
        let expectedEnd = trip.endDate
        let expectedNotes = trip.notes

        // Act
        let snapshot = TripDeletion.delete(trip, in: context)
        let restored = TripDeletion.restore(snapshot, in: context)

        // Assert
        #expect(restored.title == expectedTitle)
        #expect(restored.startDate == expectedStart)
        #expect(restored.endDate == expectedEnd)
        #expect(restored.notes == expectedNotes)
        #expect(restored.countries.map(\.nameEnglish).sorted() == ["Portugal", "Spain"])
        #expect(try context.fetch(FetchDescriptor<Trip>()).count == 1)
    }

    @Test
    func test_restore_doesNotDuplicateTheCountries() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)

        // Act
        let snapshot = TripDeletion.delete(trip, in: context)
        TripDeletion.restore(snapshot, in: context)

        // Assert
        #expect(try context.fetch(FetchDescriptor<Country>()).count == 2)
    }

    // MARK: - Undo window

    @Test
    func test_delete_viaCoordinator_offersAnUndoNamingTheTrip() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)
        let coordinator = TripDeletionCoordinator()

        // Act
        coordinator.delete(trip, in: context)

        // Assert
        #expect(coordinator.pendingUndo?.tripTitle == "Iberia")
    }

    @Test
    func test_undo_withinTheWindow_restoresTheTripAndClosesTheOffer() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)
        let coordinator = TripDeletionCoordinator()
        coordinator.delete(trip, in: context)

        // Act
        coordinator.undo(in: context)

        // Assert
        #expect(coordinator.pendingUndo == nil)
        #expect(try context.fetch(FetchDescriptor<Trip>()).count == 1)
    }

    @Test
    func test_dismissUndo_closesTheOfferWithoutRestoring() throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)
        let coordinator = TripDeletionCoordinator()
        coordinator.delete(trip, in: context)

        // Act
        coordinator.dismissUndo()

        // Assert
        #expect(coordinator.pendingUndo == nil)
        #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
    }

    @Test
    func test_undo_afterTheWindowHasPassed_isNoLongerOnOffer() async throws {

        // Arrange
        let context = try makeContext()
        let trip = try makeFullTrip(in: context)
        let coordinator = TripDeletionCoordinator()
        coordinator.delete(trip, in: context)

        // Act
        // A little past the window, so the expiry task has certainly run.
        try await Task.sleep(for: TripDeletionCoordinator.undoWindow + .milliseconds(500))

        // Assert
        #expect(coordinator.pendingUndo == nil)
        #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
    }

    @Test
    func test_delete_twiceInARow_offersUndoForTheSecondTripOnly() throws {

        // Arrange
        let context = try makeContext()
        let first = try makeFullTrip(in: context)
        let second = Trip(title: "Norway")
        context.insert(second)
        try context.save()

        // Act
        let coordinator = TripDeletionCoordinator()
        coordinator.delete(first, in: context)
        coordinator.delete(second, in: context)

        // Assert
        #expect(coordinator.pendingUndo?.tripTitle == "Norway")
    }
}
