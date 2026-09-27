//
//  DiscoverFilter.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import Foundation

/// What the user has narrowed ``DiscoverScreen`` down to.
///
/// A plain value type with a pure `apply` step, so the filtering can be reasoned about and
/// tested without a view. It deliberately carries no ranking: Discover browses, it does not
/// score.
struct DiscoverFilter: Equatable {

    // MARK: - Properties

    /// Travel tags the country must carry. A country matches when it has **any** of them,
    /// because picking two interests should widen the result, not empty it.
    var travelTags: Set<TravelTag> = []

    /// Climate the country must carry, or `nil` for any climate.
    var climate: ClimateTag?

    /// Continent the country must be on, or `nil` for all continents.
    var continent: String?

    /// Whether anything is narrowed down at all.
    var isEmpty: Bool {
        travelTags.isEmpty && climate == nil && continent == nil
    }

    // MARK: - Applying

    /// Narrows `countries` down to those matching this filter.
    ///
    /// Visited countries are dropped: Discover is for places still ahead, and a country
    /// already marked visited is not one of them. Wishlisted countries stay, so the user can
    /// see and undo what is already on the list.
    ///
    /// - Parameter countries: The countries to narrow down.
    /// - Returns: The matching countries, sorted by English name.
    func apply(to countries: [Country]) -> [Country] {

        countries
            .filter { country in

                guard country.status != .visited else { return false }

                guard travelTags.isEmpty || !travelTags.isDisjoint(with: country.travelTags)
                else {
                    return false
                }

                if let climate, !country.climateTags.contains(climate) { return false }
                if let continent, country.continent != continent { return false }

                return true
            }
            .sorted { $0.nameEnglish.localizedCaseInsensitiveCompare($1.nameEnglish) == .orderedAscending }
    }
}
