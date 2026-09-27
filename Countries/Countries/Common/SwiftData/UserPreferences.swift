//
//  UserPreferences.swift
//  Countries
//
//  Created by Max Breuning on 19.01.26.
//

import SwiftData
import Foundation

/// The user's travel preferences, the input the recommendation scoring is weighted by.
///
/// Exactly one record exists per install; use ``PreferencesService/loadOrCreate(in:)`` to
/// obtain it. The values are either derived from the travel history by
/// ``PreferenceDerivationService`` or entered by hand, which is what ``userDidCustomize``
/// distinguishes.
@Model
final class UserPreferences {

    // MARK: - Stored properties

    /// Travel tags the user is looking for, from the same vocabulary as ``Country``.
    var desiredTags: [TravelTag]

    /// Accepted climates; several may be picked, and an empty list means no climate
    /// preference at all.
    var preferredClimate: [ClimateTag]

    /// Budget constraint: the most expensive cost level still accepted, or `nil` for no
    /// limit.
    ///
    /// - Note: ``CostLevel`` is `Int`-ranked with the cheaper level first, so candidates
    ///   ranked above this one are filtered out.
    var maxCostLevel: CostLevel?

    /// Lowest acceptable safety level, for example "at least safe", or `nil` for no limit.
    ///
    /// - Note: ``SafetyLevel`` is `Int`-ranked with the safer level first, so candidates
    ///   ranked above this one are filtered out.
    var minSafety: SafetyLevel?

    /// Typical trip length the user plans for, or `nil` when it does not matter.
    var preferredDuration: TravelDuration?

    /// Season the next trip is planned for, if the user plans seasonally at all.
    var preferredSeason: Season?

    /// Which of the scoring components dominates the ranking.
    var recommendationMode: RecommendationMode

    /// When true the user edited preferences by hand and auto-derivation must not overwrite them.
    var userDidCustomize: Bool

    /// Last time these preferences changed.
    ///
    /// - Note: Read for display in the settings sheet and as the sort key that picks the newest
    ///   record in ``PreferencesService/loadOrCreate(in:)``. It does **not** influence the
    ///   recommendation ranking: ties there break on `score` descending, then `iso2` ascending,
    ///   with no jitter involved.
    var updatedAt: Date

    // MARK: - Init

    /// Creates a preference record; every parameter has a neutral default, so
    /// `UserPreferences()` is the "no preferences stated yet" case.
    ///
    /// - Parameters:
    ///   - desiredTags: Wanted travel tags. Defaults to an empty list.
    ///   - preferredClimate: Accepted climates. Defaults to an empty list.
    ///   - maxCostLevel: Budget ceiling. Defaults to `nil`, meaning no limit.
    ///   - minSafety: Lowest accepted safety level. Defaults to `nil`, meaning no limit.
    ///   - preferredDuration: Typical trip length. Defaults to `nil`.
    ///   - preferredSeason: Season of the next trip. Defaults to `nil`.
    ///   - recommendationMode: Ranking mode. Defaults to ``RecommendationMode/balanced``.
    ///   - userDidCustomize: Whether the values were entered by hand. Defaults to `false`.
    ///   - updatedAt: Timestamp of the last change. Defaults to `.now`.
    init(desiredTags: [TravelTag] = [],
         preferredClimate: [ClimateTag] = [],
         maxCostLevel: CostLevel? = nil,
         minSafety: SafetyLevel? = nil,
         preferredDuration: TravelDuration? = nil,
         preferredSeason: Season? = nil,
         recommendationMode: RecommendationMode = .balanced,
         userDidCustomize: Bool = false,
         updatedAt: Date = .now) {

        self.desiredTags = desiredTags
        self.preferredClimate = preferredClimate
        self.maxCostLevel = maxCostLevel
        self.minSafety = minSafety
        self.preferredDuration = preferredDuration
        self.preferredSeason = preferredSeason
        self.recommendationMode = recommendationMode
        self.userDidCustomize = userDidCustomize
        self.updatedAt = updatedAt
    }
}

// MARK: - RecommendationMode

/// How the recommendation scoring weighs its components against each other.
///
/// - Note: The mode selects a weight set and reshapes the components, but the score stays
///   inside `0...1` for every mode.
enum RecommendationMode: String, Codable, CaseIterable {

    /// Preference-led, with a noticeable amount of similarity and diversity mixed in.
    case balanced

    /// Similarity to the most recent trips dominates, diversity is almost switched off.
    case similarToRecent

    /// Continent diversity dominates, similarity is almost switched off.
    case exploreNew
}
