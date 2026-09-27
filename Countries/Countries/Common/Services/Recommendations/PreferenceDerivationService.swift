//
//  PreferenceDerivationService.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//

import Foundation

/// Infers default travel preferences from the countries the user marked and the trips they logged.
///
/// The derivation is intentionally conservative: every result is optional and stays `nil` while the
/// history is too thin to say anything meaningful. It is only applied while
/// ``UserPreferences/userDidCustomize`` is `false`; once the user edits preferences by hand,
/// ``PreferencesService`` stops calling into this type.
///
/// - Note: Purely static and side-effect free; nothing here touches the model context. The
///   derivation works fully offline.
enum PreferenceDerivationService {

    // MARK: - Types

    /// The set of preferences that can be derived from history.
    ///
    /// Every property is optional or empty when the history did not contain enough signal,
    /// so callers can copy the values over verbatim without extra guarding.
    struct AutoPreferences {
        /// Most frequent travel tags across the weighted history, at most
        /// ``PreferenceDerivationService/Constants/maxDesiredTags`` entries, strongest first.
        var desiredTags: [TravelTag]
        /// Most frequent climate tags across the weighted history, at most
        /// ``PreferenceDerivationService/Constants/maxPreferredClimateTags`` entries, strongest first.
        var preferredClimate: [ClimateTag]
        /// Budget ceiling derived from the median cost level, biased upwards to stay tolerant.
        /// `nil` when the history is too small.
        var maxCostLevel: CostLevel?
        /// Safety floor derived from the median safety level, biased downwards to stay permissive.
        /// `nil` when the history is too small.
        var minSafety: SafetyLevel?
        /// Most common duration across the logged trips, `nil` when too few trips exist.
        var preferredDuration: TravelDuration?
        /// Most common season across the logged trips, `nil` when too few trips exist.
        var preferredSeason: Season?
    }

    // MARK: - Constants

    /// Thresholds and bounds used by the derivation. Changing a value here changes every
    /// auto-derived preference, so treat them as tuned input.
    private enum Constants {

        /// Number of travel tags carried over into ``AutoPreferences/desiredTags``.
        static let maxDesiredTags = 4

        /// Number of climate tags carried over into ``AutoPreferences/preferredClimate``.
        static let maxPreferredClimateTags = 2

        /// Minimum number of weighted countries before tag frequencies are considered meaningful.
        static let minCountriesForTagDerivation = 2

        /// Minimum number of weighted countries before a median cost/safety level is derived.
        static let minCountriesForLevelDerivation = 3

        /// Minimum number of trips before the most common duration/season is derived.
        static let minTripsForTripDerivation = 2

        /// Steps the median cost level is shifted upwards by, so the budget stays tolerant.
        static let costToleranceBias = 1

        /// Steps the median safety level is shifted downwards by, so the filter stays permissive.
        static let safetyToleranceBias = 1

        /// Highest ``CostLevel`` rank, used as the clamp for the upward cost bias.
        ///
        /// Read from `allCases` so it follows the enum; the fallback names the case that currently
        /// holds the bound in `Country+Enums.swift` (`veryExpensive`, raw value 5).
        static let highestCostRank = CostLevel.allCases.last?.rawValue
            ?? CostLevel.veryExpensive.rawValue

        /// Lowest ``SafetyLevel`` rank, used as the clamp for the downward safety bias.
        ///
        /// Read from `allCases` so it follows the enum; the fallback names the case that currently
        /// holds the bound in `Country+Enums.swift` (`verySafe`, raw value 1).
        static let lowestSafetyRank = SafetyLevel.allCases.first?.rawValue
            ?? SafetyLevel.verySafe.rawValue
    }

    // MARK: - Public API

    /// Derives preferences from the user's travel history.
    ///
    /// Visited countries carry twice the weight of wishlisted ones: the visited list is fed into the
    /// frequency counts twice, the wishlist once. Wishlisted countries describe taste, visited ones
    /// describe proven behaviour.
    ///
    /// - Parameters:
    ///   - visitedCountries: Countries with ``CountryStatus/visited``; weighted twice.
    ///   - wishlistedCountries: Countries with ``CountryStatus/wishlist``; weighted once.
    ///   - trips: The user's trips, used only for duration and season.
    /// - Returns: The derived ``AutoPreferences``; individual fields stay `nil`/empty when the
    ///   history holds too little signal.
    static func derive(
        visitedCountries: [Country],
        wishlistedCountries: [Country],
        trips: [Trip]
    ) -> AutoPreferences {

        // Weighting: visited counts more heavily than wishlist
        let weightedCountries =
        visitedCountries +
        visitedCountries +        // visited x2
        wishlistedCountries       // wishlist x1

        return AutoPreferences(
            desiredTags: topTravelTags(from: weightedCountries, take: Constants.maxDesiredTags),
            preferredClimate: topClimateTags(from: weightedCountries,
                                             take: Constants.maxPreferredClimateTags),
            maxCostLevel: derivedMaxCostLevel(from: weightedCountries),
            minSafety: derivedMinSafetyLevel(from: weightedCountries),
            preferredDuration: mostCommonTripDuration(from: trips),
            preferredSeason: mostCommonTripSeason(from: trips)
        )
    }

    // MARK: - Tags

    /// The most frequent travel tags in `countries`, strongest first.
    ///
    /// - Parameters:
    ///   - countries: The weighted country list; duplicates are intentional and act as weights.
    ///   - take: Maximum number of tags to return.
    /// - Returns: Up to `take` tags, or an empty array when the list is too short to be meaningful.
    private static func topTravelTags(from countries: [Country], take: Int) -> [TravelTag] {
        guard countries.count >= Constants.minCountriesForTagDerivation else { return [] }

        var counts: [TravelTag: Int] = [:]
        for country in countries {
            for tag in country.travelTags {
                counts[tag, default: 0] += 1
            }
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(take)
            .map(\.key)
    }

    /// The most frequent climate tags in `countries`, strongest first.
    ///
    /// - Parameters:
    ///   - countries: The weighted country list; duplicates are intentional and act as weights.
    ///   - take: Maximum number of tags to return.
    /// - Returns: Up to `take` tags, or an empty array when the list is too short to be meaningful.
    private static func topClimateTags(from countries: [Country], take: Int) -> [ClimateTag] {
        guard countries.count >= Constants.minCountriesForTagDerivation else { return [] }

        var counts: [ClimateTag: Int] = [:]
        for country in countries {
            for tag in country.climateTags {
                counts[tag, default: 0] += 1
            }
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(take)
            .map(\.key)
    }

    // MARK: - Cost and Safety

    /// The budget ceiling derived from the median cost level of `countries`.
    ///
    /// ``CostLevel`` is ranked so that a lower raw value is cheaper. The median is therefore shifted
    /// *upwards* by ``Constants/costToleranceBias`` and clamped to ``Constants/highestCostRank``:
    /// the derived ceiling should never be stricter than the user's own history.
    ///
    /// - Parameter countries: The weighted country list.
    /// - Returns: The biased cost ceiling, or `nil` when fewer than
    ///   ``Constants/minCountriesForLevelDerivation`` countries are known.
    private static func derivedMaxCostLevel(from countries: [Country]) -> CostLevel? {
        let values = countries.map { $0.costLevel.rawValue }.sorted()
        guard values.count >= Constants.minCountriesForLevelDerivation else { return nil }

        let median = values[values.count / 2]

        // Bias UPWARDS (but clamp)
        let biased = min(median + Constants.costToleranceBias, Constants.highestCostRank)
        return CostLevel(rawValue: biased)
    }

    /// The safety floor derived from the median safety level of `countries`.
    ///
    /// ``SafetyLevel`` is ranked so that a lower raw value is safer, and the recommendation filter
    /// rejects anything ranked *above* this value. The median is therefore shifted *downwards* by
    /// ``Constants/safetyToleranceBias`` and clamped to ``Constants/lowestSafetyRank``, which keeps
    /// the derived filter realistic instead of overly strict.
    ///
    /// - Parameter countries: The weighted country list.
    /// - Returns: The biased safety floor, or `nil` when fewer than
    ///   ``Constants/minCountriesForLevelDerivation`` countries are known.
    private static func derivedMinSafetyLevel(from countries: [Country]) -> SafetyLevel? {
        let values = countries.map { $0.safetyLevel.rawValue }.sorted()
        guard values.count >= Constants.minCountriesForLevelDerivation else { return nil }

        let median = values[values.count / 2]

        // Bias DOWNWARDS (but clamp)
        let biased = max(median - Constants.safetyToleranceBias, Constants.lowestSafetyRank)
        return SafetyLevel(rawValue: biased)
    }

    // MARK: - Trips

    /// The duration that occurs most often across `trips`.
    ///
    /// - Parameter trips: The user's trips; trips without a duration are ignored.
    /// - Returns: The most frequent duration, or `nil` when fewer than
    ///   ``Constants/minTripsForTripDerivation`` trips exist or none carries a duration.
    private static func mostCommonTripDuration(from trips: [Trip]) -> TravelDuration? {
        guard trips.count >= Constants.minTripsForTripDerivation else { return nil }

        var counts: [TravelDuration: Int] = [:]
        for trip in trips {
            if let duration = trip.duration {
                counts[duration, default: 0] += 1
            }
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// The season that occurs most often across `trips`.
    ///
    /// - Parameter trips: The user's trips; trips without a season are ignored.
    /// - Returns: The most frequent season, or `nil` when fewer than
    ///   ``Constants/minTripsForTripDerivation`` trips exist or none carries a season.
    private static func mostCommonTripSeason(from trips: [Trip]) -> Season? {
        guard trips.count >= Constants.minTripsForTripDerivation else { return nil }

        var counts: [Season: Int] = [:]
        for trip in trips {
            if let season = trip.season {
                counts[season, default: 0] += 1
            }
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }
}
