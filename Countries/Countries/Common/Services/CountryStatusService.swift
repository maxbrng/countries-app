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
}
