//
//  HomeCountry.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData

/// The one country the user lives in.
///
/// Stored in `UserDefaults` rather than as a field on ``Country``, for two reasons. The schema
/// is frozen for 1.0 — see ``CountriesSchemaV1`` — so a new stored property would be a
/// migration. And "exactly one" is a property of the whole set, which a boolean on each of two
/// hundred and fifty rows cannot enforce: a single code can only ever name one country, while
/// a flag can be true on all of them.
///
/// - Note: Home implies visited, because a country you live in is one you have been to. It is
///   *not* counted separately anywhere: the statistics count visited countries, and the home
///   country is one of them rather than an extra.
@MainActor
enum HomeCountry {

    /// Key of the stored ISO2 code.
    static let storageKey = "homeCountryISO2"

    /// ISO2 code of the home country, or `nil` when none has been picked.
    static var iso2: String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    /// Sets the home country and marks it visited.
    ///
    /// - Parameters:
    ///   - code: ISO2 code of the new home country, or `nil` to clear it.
    ///   - context: The model context holding the countries.
    /// - Throws: Any error from the status write.
    /// - Note: Clearing the home country does **not** un-visit it. Moving away is not the same
    ///   as never having been there, and a setting that silently erased a visit would be worse
    ///   than one that leaves a country marked.
    static func set(_ code: String?, in context: ModelContext) throws {

        guard let code, !code.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        let uppercased = code.uppercased()
        UserDefaults.standard.set(uppercased, forKey: storageKey)

        try CountryStatusService.setStatus(.visited,
                                           forCountriesWithISO2: [uppercased],
                                           in: context)
    }

    /// Whether `country` is the home country.
    ///
    /// - Parameter country: The country to test.
    static func isHome(_ country: Country) -> Bool {
        iso2 == country.iso2
    }

    /// Forgets the home country without touching any status.
    ///
    /// Used by the data reset, which erases the statuses separately.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
