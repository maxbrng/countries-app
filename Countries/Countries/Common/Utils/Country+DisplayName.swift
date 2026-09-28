//
//  Country+DisplayName.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

// The country names the user sees. Kept out of ``Country`` itself, which stays a plain model,
// and kept in one place so no screen has to decide for itself which language a country is in.

extension Country {

    /// Languages a country name is resolved against, most preferred first.
    ///
    /// The bundle's own localizations rather than the device's full language list, so a name
    /// always matches the rest of the interface: an app running in German says "Frankreich",
    /// including on a device whose second language the app does not ship. English closes the
    /// list, because every country has an English name and not every one has a German one.
    private static let preferredLanguageCodes: [String] =
        Bundle.main.preferredLocalizations + ["en"]

    /// The country's name in the language the app is currently showing.
    ///
    /// - Note: Resolving it means decoding ``translationsData``, so the result is cached on the
    ///   object. Sorting two hundred and fifty countries compares each name several times, and
    ///   a JSON decode per comparison is not something a list can afford.
    var displayName: String {

        if let cachedDisplayName { return cachedDisplayName }

        let name = displayName(preferredLanguageCodes: Self.preferredLanguageCodes)
        cachedDisplayName = name

        return name
    }

    /// Whether this country answers to `query`.
    ///
    /// Matches the displayed name, the English name and both ISO codes, so a German user finds
    /// "Frankreich" and an English one still finds "France" — on the same device, in the same
    /// list, without knowing which name the app happens to be showing.
    ///
    /// - Parameter query: Raw search text; whitespace is trimmed and case is ignored.
    /// - Returns: `true` when any of the names or codes contains the query.
    func matches(searchQuery query: String) -> Bool {

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return true }

        let haystack: [String] = [displayName, nameEnglish, iso2] + [iso3].compactMap { $0 }

        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

// MARK: - Ordering

extension Sequence where Element == Country {

    /// Sorted by the name the user actually sees.
    ///
    /// Uses the locale's own collation, which is what puts "Ägypten" next to "Afghanistan" in
    /// German rather than after "Zypern".
    ///
    /// - Parameter ascending: `false` reverses the order. Defaults to `true`.
    /// - Returns: The countries in display-name order.
    func sortedByDisplayName(ascending: Bool = true) -> [Country] {

        sorted { first, second in

            let comparison = first.displayName.localizedStandardCompare(second.displayName)

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
