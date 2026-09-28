//
//  CountryStatusService.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import Foundation
import SwiftData

/// Single entry point for changing a country's ``CountryStatus``.
///
/// Every status control in the app routes through here so the toggle behaviour stays identical
/// across the country list, the detail screen and the map's quick action panel.
///
/// - Note: `@MainActor`, because it works directly on SwiftData `@Model` objects.
@MainActor
enum CountryStatusService {

    /// Whether toggling `status` would withdraw ``CountryStatus/visited`` from a country that
    /// still belongs to trips.
    ///
    /// Withdrawing the status is not the same as saying the journey never happened, so the
    /// trips are deliberately left alone — this is what lets the caller say so before the
    /// change rather than leave the user to discover it.
    ///
    /// - Parameters:
    ///   - status: The status the control stands for.
    ///   - country: The country the control belongs to.
    /// - Returns: `true` when the toggle clears ``CountryStatus/visited`` and at least one
    ///   trip would remain.
    static func withdrawalLeavesTrips(_ status: CountryStatus, for country: Country) -> Bool {

        guard status == .visited, country.status == .visited else { return false }

        return !country.trips.isEmpty
    }

    /// Applies `status`, or clears it when the country already carries it.
    ///
    /// - Parameters:
    ///   - status: The status to apply.
    ///   - country: The country to change.
    ///   - context: The model context holding `country`.
    /// - Throws: Any error from the save.
    static func toggleStatus(_ status: CountryStatus,
                             for country: Country,
                             in context: ModelContext) throws {

        let newStatus: CountryStatus = (country.status == status) ? .none : status
        try setStatus(newStatus, for: country, in: context)
    }

    /// Sets `status` on `country` and saves.
    ///
    /// A no-op when the country already carries `status`, so repeated calls do not save.
    ///
    /// - Parameters:
    ///   - status: The status to store.
    ///   - country: The country to change.
    ///   - context: The model context holding `country`.
    /// - Throws: Any error from the save.
    static func setStatus(_ status: CountryStatus,
                          for country: Country,
                          in context: ModelContext) throws {

        guard country.status != status else { return }

        country.status = status
        try context.save()
    }

    /// Applies `status` to every country whose ``Country/iso2`` is in `codes`.
    ///
    /// One save for the whole set rather than one per country: the first launch can hand in
    /// two hundred codes at once, and that is two hundred round trips to the store otherwise.
    ///
    /// - Parameters:
    ///   - status: The status to store.
    ///   - codes: ISO2 codes, matched case-insensitively against the stored uppercase code.
    ///   - context: The model context holding the countries.
    /// - Returns: How many countries actually changed. Zero is a valid answer — a user who
    ///   selected nothing has said something, and the caller should not treat it as a failure.
    /// - Throws: Any error from the fetch or the save.
    @discardableResult
    static func setStatus(_ status: CountryStatus,
                          forCountriesWithISO2 codes: Set<String>,
                          in context: ModelContext) throws -> Int {

        guard !codes.isEmpty else { return 0 }

        let wanted = Set(codes.map { $0.uppercased() })
        let countries = try context.fetch(FetchDescriptor<Country>())

        var changed = 0
        for country in countries where wanted.contains(country.iso2) && country.status != status {
            country.status = status
            changed += 1
        }

        guard changed > 0 else { return 0 }

        try context.save()

        return changed
    }
}
