//
//  CountriesListViewModel.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import Combine

enum CountryStatusFilter: Sendable, CaseIterable, Identifiable {
    case all
    case visited
    case wishlist

    var id: String { String(describing: self) }
    var title: String {
        switch self {
        case .all: return "All"
        case .visited: return "Visited"
        case .wishlist: return "Wishlist"
        }
    }
}

@MainActor
final class CountriesListViewModel: ObservableObject {

    @Published var search: String = ""
    @Published var filter: CountryStatusFilter = .all
    @Published var sortAscending: Bool = true

    struct CountryGroup {
        let continentCode: String
        let title: String
        let countries: [Country]
    }

    func filteredCountries(from allCountries: [Country]) -> [Country] {
        
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
        let searchResult = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchResult.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchResult) ||
                $0.iso2.localizedCaseInsensitiveContains(searchResult)
            }
        }

        // Sort
        result.sort {
            let comparisonResult = $0.name.localizedCaseInsensitiveCompare($1.name)
            return sortAscending ? (comparisonResult == .orderedAscending) : (comparisonResult == .orderedDescending)
        }

        return result
    }

    func groups(from countries: [Country]) -> [CountryGroup] {
        
        let dict = Dictionary(grouping: countries, by: { $0.continent ?? "??" })

        var groups = dict.map { code, items in
            CountryGroup(
                continentCode: code,
                title: continentTitle(for: code),
                countries: items
            )
        }

        // sort groups by title
        groups.sort { sortAscending ? $0.title < $1.title : $0.title > $1.title }
        
        return groups
    }

    private func continentTitle(for code: String) -> String {
        switch code {
        case "AF": "Africa"
        case "AN": "Antarctica"
        case "AS": "Asia"
        case "EU": "Europe"
        case "NA": "North America"
        case "OC": "Oceania"
        case "SA": "South America"
        case "??": "Unknown"
        default: code
        }
    }
}
