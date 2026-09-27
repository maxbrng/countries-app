//
//  PreferencesService.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "Preferences")

/// Single entry point for changing a country's ``CountryStatus`` and for keeping the auto-derived
/// ``UserPreferences`` in sync with the user's travel history.
///
/// Every status control in the app routes through here so that the derived preferences, and with
/// them the recommendations, can never drift away from the stored statuses.
///
/// - Note: `@MainActor`, because it works directly on SwiftData `@Model` objects.
@MainActor
enum PreferencesService {

    // MARK: - Preferences record

    /// Returns the app's single ``UserPreferences`` record, creating it if needed.
    ///
    /// Older installs could hold one record per mock profile. Those are collapsed
    /// into a single record here so the store converges on first launch.
    ///
    /// - Parameter context: The model context to read from and, if needed, write to.
    /// - Returns: The newest existing record, or a freshly inserted one.
    /// - Throws: Any error from the underlying fetch or save.
    @discardableResult
    static func loadOrCreate(in context: ModelContext) throws -> UserPreferences {

        let existing = try context.fetch(
            FetchDescriptor<UserPreferences>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )

        if let preferences = existing.first {
            for stale in existing.dropFirst() {
                context.delete(stale)
            }
            if existing.count > 1 {
                try context.save()
            }
            return preferences
        }

        let created = UserPreferences()
        context.insert(created)
        try context.save()

        return created
    }

    // MARK: - Country status

    /// Applies `status`, or clears it when the country already has it.
    /// This is the toggle behaviour every status control in the app uses.
    ///
    /// - Parameters:
    ///   - status: The status to apply.
    ///   - country: The country to change.
    ///   - context: The model context holding `country`.
    /// - Throws: Any error from the derivation or the save.
    static func toggleStatus(_ status: CountryStatus,
                             for country: Country,
                             in context: ModelContext) throws {

        let newStatus: CountryStatus = (country.status == status) ? .none : status
        try setStatus(newStatus, for: country, in: context)
    }

    /// Sets `status` on `country`, refreshes the derived preferences and saves.
    ///
    /// A no-op when the country already carries `status`, so repeated calls neither save nor
    /// re-derive.
    ///
    /// - Parameters:
    ///   - status: The status to store.
    ///   - country: The country to change.
    ///   - context: The model context holding `country`.
    /// - Throws: Any error from the derivation or the save.
    static func setStatus(_ status: CountryStatus,
                          for country: Country,
                          in context: ModelContext) throws {

        guard country.status != status else { return }

        country.status = status
        try refreshDerivedPreferences(in: context)
        try context.save()
    }

    // MARK: - Derivation

    /// Re-derives preferences from the user's history unless they were edited by hand.
    ///
    /// Returns without doing anything while ``UserPreferences/userDidCustomize`` is `true`; that flag
    /// is what protects manual edits from being overwritten.
    ///
    /// Does not save; callers batch this with their own `save()`.
    ///
    /// - Parameter context: The model context to read the history from and write the derived
    ///   preferences into.
    /// - Throws: Any error from the fetches or from ``loadOrCreate(in:)``.
    static func refreshDerivedPreferences(in context: ModelContext) throws {

        let preferences = try loadOrCreate(in: context)
        guard preferences.userDidCustomize == false else { return }

        let allCountries = try context.fetch(FetchDescriptor<Country>())
        let trips = try context.fetch(
            FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )

        let derived = PreferenceDerivationService.derive(
            visitedCountries: allCountries.filter { $0.status == .visited },
            wishlistedCountries: allCountries.filter { $0.status == .wishlist },
            trips: trips
        )

        preferences.desiredTags = derived.desiredTags
        preferences.preferredClimate = derived.preferredClimate
        preferences.maxCostLevel = derived.maxCostLevel
        preferences.minSafety = derived.minSafety
        preferences.preferredDuration = derived.preferredDuration
        preferences.preferredSeason = derived.preferredSeason
        preferences.updatedAt = .now

        logger.debug("Derived preferences refreshed.")
    }
}
