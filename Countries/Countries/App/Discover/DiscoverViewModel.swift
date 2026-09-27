//
//  DiscoverViewModel.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import Foundation
import Observation

/// Owns the recommendation list so scoring runs on explicit input changes
/// instead of on every SwiftUI body evaluation.
///
/// ``updateIfNeeded(countries:trips:preferences:topN:)`` is cheap to call from `onAppear` and
/// `onChange`: it hashes its inputs and only re-runs ``RecommendationService`` when that hash moved.
@Observable
@MainActor
final class DiscoverViewModel {

    // MARK: - State

    /// The current recommendations, highest score first. Empty while no preferences exist.
    private(set) var recommendations: [RecommendationService.Recommendation] = []

    /// Signature of the inputs the current `recommendations` were computed from.
    private var lastInputSignature: Int?

    /// The recommended countries in ranking order, for views that only need the country.
    var recommendedCountries: [Country] {
        recommendations.map(\.country)
    }

    // MARK: - Updating

    /// Recomputes only when the relevant inputs actually changed.
    ///
    /// - Parameters:
    ///   - countries: Every known country, including the marked ones.
    ///   - trips: The user's trips, most recent first.
    ///   - preferences: The preferences to score against. `nil` clears the list.
    ///   - topN: Maximum number of recommendations to keep. Defaults to `25`.
    func updateIfNeeded(countries: [Country],
                        trips: [Trip],
                        preferences: UserPreferences?,
                        topN: Int = 25) {

        guard let preferences else {
            recommendations = []
            lastInputSignature = nil
            return
        }

        let signature = inputSignature(countries: countries,
                                       trips: trips,
                                       preferences: preferences,
                                       topN: topN)

        guard signature != lastInputSignature else { return }
        lastInputSignature = signature

        recommendations = RecommendationService.recommendTopCountries(
            allCountries: countries,
            trips: trips,
            preferences: preferences,
            topN: topN
        )
    }

    // MARK: - Input signature

    /// Hashes everything the scoring result depends on.
    ///
    /// Unmarked countries are skipped on purpose: they are candidates, but changing one cannot change
    /// the ranking as long as its status stays ``CountryStatus/none``, so only the total count is
    /// folded in.
    ///
    /// - Parameters:
    ///   - countries: Every known country.
    ///   - trips: The user's trips.
    ///   - preferences: The preferences to score against.
    ///   - topN: Maximum number of recommendations.
    /// - Returns: A hash value that changes whenever the recommendations would change.
    private func inputSignature(countries: [Country],
                                trips: [Trip],
                                preferences: UserPreferences,
                                topN: Int) -> Int {

        var hasher = Hasher()

        // Only marked countries influence the result.
        for country in countries where country.status != .none {
            hasher.combine(country.iso2)
            hasher.combine(country.status)
        }

        hasher.combine(countries.count)
        hasher.combine(trips.count)

        hasher.combine(preferences.desiredTags)
        hasher.combine(preferences.preferredClimate)
        hasher.combine(preferences.maxCostLevel)
        hasher.combine(preferences.minSafety)
        hasher.combine(preferences.preferredDuration)
        hasher.combine(preferences.preferredSeason)
        hasher.combine(preferences.recommendationMode)
        hasher.combine(topN)

        return hasher.finalize()
    }
}
