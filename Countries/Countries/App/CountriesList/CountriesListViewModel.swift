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
    ///   - searchText: Raw field contents; trimmed, and matched against the displayed name,
    ///     the English name and both ISO codes — see ``Country/matches(searchQuery:)``.
    /// - Returns: The matching countries sorted by the name the user sees.
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
            result = result.filter { $0.matches(searchQuery: searchResult) }
        }

        return result.sortedByDisplayName(ascending: sortAscending)
    }

    // MARK: - Grouping

    /// Groups countries by continent for the sectioned list.
    ///
    /// - Parameter countries: Countries to group; their order is preserved inside a group.
    /// - Returns: Groups sorted by title, honouring ``sortAscending``.
    func groups(from countries: [Country]) -> [CountryGroup] {

        let dict = Dictionary(grouping: countries, by: { $0.continent ?? ContinentName.unknownCode })

        var groups = dict.map { code, items in
            CountryGroup(
                continentCode: code,
                title: ContinentName.name(for: code),
                countries: items
            )
        }

        // Sorted by the translated title, so the headings follow the same alphabet as the
        // rows under them.
        groups.sort {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }

        return groups
    }

}
