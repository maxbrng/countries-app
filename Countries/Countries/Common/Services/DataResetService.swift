//
//  DataResetService.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "Reset")

/// Erases everything the user created and returns the app to its first-launch state.
///
/// - Note: `@MainActor`, because it works directly on SwiftData `@Model` objects.
@MainActor
enum DataResetService {

    // MARK: - Nested types

    /// What a reset would remove.
    ///
    /// The confirmation names these numbers rather than describing the reset in general terms,
    /// so what the user is warned about is what actually happens.
    struct Summary: Equatable {

        /// Countries currently marked as visited.
        let visitedCount: Int

        /// Countries currently on the wishlist.
        let wishlistCount: Int

        /// Trips currently stored.
        let tripCount: Int

        /// Whether a reset would remove anything at all.
        var isEmpty: Bool {
            visitedCount == 0 && wishlistCount == 0 && tripCount == 0
        }
    }

    /// Stored settings that a reset returns to their defaults.
    private static let resetDefaultsKeys = ["showOnlyUNMembers", MapAppearance.storageKey]

    // MARK: - Inspection

    /// Counts what a reset would remove.
    ///
    /// - Parameter context: The model context to read from.
    /// - Returns: The counts shown in the confirmation.
    /// - Throws: Any error from the underlying fetches.
    static func summary(in context: ModelContext) throws -> Summary {

        let countries = try context.fetch(FetchDescriptor<Country>())

        return Summary(
            visitedCount: countries.count { $0.status == .visited },
            wishlistCount: countries.count { $0.status == .wishlist },
            tripCount: try context.fetchCount(FetchDescriptor<Trip>())
        )
    }

    // MARK: - Reset

    /// Deletes every trip and country, re-seeds the countries and clears the stored settings.
    ///
    /// Countries are deleted rather than reset field by field so the seed file becomes the
    /// single source of truth again, exactly as on a fresh install.
    ///
    /// - Parameter context: The model context holding the data.
    /// - Throws: Any error from the deletion, the save or the re-seed.
    static func resetEverything(in context: ModelContext) throws {

        // Deleted one by one, not with `delete(model:)`. A batch delete cannot maintain the
        // many-to-many inverse between Trip and Country and fails with
        // "Constraint trigger violation: mandatory MTM nullify inverse on Trip/countries".
        //
        // Trips go first, so the countries are still there while their inverse is cleared.
        for trip in try context.fetch(FetchDescriptor<Trip>()) {
            context.delete(trip)
        }
        try context.save()

        for country in try context.fetch(FetchDescriptor<Country>()) {
            context.delete(country)
        }
        try context.save()

        for key in resetDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // "First-launch state" includes the first launch itself. Without this the reset would
        // leave a user who has just erased everything on an empty map with no way back to the
        // screen that offered to fill it.
        OnboardingState.reset()
        HomeCountry.reset()

        try CountrySeeder.seedIfNeeded(in: context)

        logger.info("Data reset completed; countries re-seeded.")
    }
}
