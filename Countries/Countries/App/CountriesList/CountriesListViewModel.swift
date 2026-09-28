//
//  CountriesListViewModel.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import Combine

/// Status filter of the country list and of the map's search sheet.
enum CountryStatusFilter: Sendable, CaseIterable, Identifiable {
    /// No filtering; every country passes.
    case all
    /// Only countries marked ``CountryStatus/visited``.
    case visited
    /// Only countries marked ``CountryStatus/wishlist``.
    case wishlist

    /// Stable identity derived from the case name.
    var id: String { String(describing: self) }

    /// Display title of the filter, looked up in the string catalog.
    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .visited: return "Visited"
        case .wishlist: return "Wishlist"
        }
    }
}

/// Filtering, searching, sorting and continent grouping for ``CountriesList``.
///
/// - Note: Holds no country data of its own; ``CountriesList`` owns the `@Query` and hands
///   the countries in on every call.
@MainActor
final class CountriesListViewModel: ObservableObject {

    // MARK: - Constants

    /// Placeholder continent code for countries without a continent.
    private static let unknownContinentCode = "??"

    // MARK: - Published state

    /// Status filter selected in the segmented header. Defaults to ``CountryStatusFilter/all``.
    @Published var filter: CountryStatusFilter = .all

    /// Sort direction for both countries and continent groups. Defaults to `true` (A to Z).
    @Published var sortAscending: Bool = true

    // MARK: - Nested types

    /// One continent section of the grouped list.
    struct CountryGroup {
        /// Two-letter continent code, e.g. `"EU"`, or `"??"` when unknown.
        let continentCode: String
        /// Display title of the continent.
        let title: String
        /// Countries of this continent, in the list's current sort order.
        let countries: [Country]
    }

    // MARK: - Filtering

    /// Applies the status filter, the search term and the sort direction, in that order.
    ///
    /// Search text is supplied by the call site: the search tab owns the field, the
    /// pushed screen has none.
    ///
    /// - Parameters:
    ///   - allCountries: The countries to narrow down.
    ///   - searchText: Raw field contents; trimmed, and matched case-insensitively against
    ///     the English name and the ISO2 code.
    /// - Returns: The matching countries sorted by English name.
    func filteredCountries(from allCountries: [Country], searchText: String) -> [Country] {

        var result = allCountries

        // Filter
        switch filter {
        case .all:
            break
        case .visited:
            result = result.filter { $0.status == .visited }
        case .wishlist:
            result = result.filter { $0.status == .wishlist }
        }

        // Search
        let searchResult = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchResult.isEmpty {
            result = result.filter {
                $0.nameEnglish.localizedCaseInsensitiveContains(searchResult) ||
                $0.iso2.localizedCaseInsensitiveContains(searchResult)
            }
        }

        // Sort
        result.sort {
            let comparisonResult = $0.nameEnglish.localizedCaseInsensitiveCompare($1.nameEnglish)
            return sortAscending
                ? (comparisonResult == .orderedAscending)
                : (comparisonResult == .orderedDescending)
        }

        return result
    }

    // MARK: - Grouping

    /// Groups countries by continent for the sectioned list.
    ///
    /// - Parameter countries: Countries to group; their order is preserved inside a group.
    /// - Returns: Groups sorted by title, honouring ``sortAscending``.
    func groups(from countries: [Country]) -> [CountryGroup] {

        let dict = Dictionary(grouping: countries, by: { $0.continent ?? Self.unknownContinentCode })

        var groups = dict.map { code, items in
            CountryGroup(
                continentCode: code,
                title: continentTitle(for: code),
                countries: items
            )
        }

        // Sort groups by title
        groups.sort { sortAscending ? $0.title < $1.title : $0.title > $1.title }

        return groups
    }

    /// Display title for a continent code.
    ///
    /// - Parameter code: Two-letter continent code as stored on ``Country``.
    /// - Returns: The English continent name, or `code` itself for an unrecognised value.
    private func continentTitle(for code: String) -> String {
        switch code {
        case "AF": "Africa"
        case "AN": "Antarctica"
        case "AS": "Asia"
        case "EU": "Europe"
        case "NA": "North America"
        case "OC": "Oceania"
        case "SA": "South America"
        case Self.unknownContinentCode: "Unknown"
        default: code
        }
    }
}
