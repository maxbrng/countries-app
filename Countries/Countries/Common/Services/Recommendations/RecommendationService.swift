//
//  RecommendationService.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//

import Foundation

/// Scores countries the user has not marked yet and returns the best matches with a
/// human-readable reason for each one.
///
/// Every recommendation is explainable and is based on three groups of input:
///
/// - user preferences as structured context (``UserPreferences``),
/// - travel history (trips and visited countries),
/// - country attributes (travel tags, climate, cost, safety, continent).
///
/// The score is a weighted sum of four independent components, each of which is itself in `0...1`:
///
/// - **preference match** how well the country's tags, climate and travel style fit
///   ``UserPreferences``,
/// - **similarity to recent trips** Jaccard overlap of travel plus climate tag signatures against
///   the most recently visited countries,
/// - **continent diversity** how under-represented the country's continent is in the user's
///   history,
/// - **wishlist affinity** how well the country matches the taste expressed by the wishlist.
///
/// The per-mode weights are normalised so that they sum to `1.0`, which is why the weighted sum can
/// never leave `0...1`. ``RecommendationMode`` additionally reshapes single components with `pow`
/// exponents; those transforms are monotonic on `0...1`, so they change the emphasis of a mode
/// without changing the range.
///
/// - Note: Purely static and side-effect free. Nothing here mutates the model context, and the
///   result is fully deterministic for a given input.
enum RecommendationService {

    // MARK: - Public Types

    /// A single scored recommendation together with the reason it was picked.
    struct Recommendation: Identifiable {

        /// Identity for SwiftUI only; it is regenerated on every scoring pass.
        let id = UUID()

        /// The recommended country. Never a visited or wishlisted one.
        let country: Country

        /// Always clamped to 0...1
        let score: Double

        /// Short, user-facing reason naming the mode and the strongest component.
        /// Every recommendation carries one, so the ranking stays explainable.
        let explanation: String
    }

    // MARK: - Tuning

    /// Intent weights per ``RecommendationMode``, normalised in ``normalizedWeights(for:)`` before
    /// they are applied. The relative sizes are tuned; changing one changes every recommendation.
    private enum ModeWeights {

        /// Preference-led, with a noticeable amount of similarity and diversity mixed in.
        static let balanced = Weights(preference: 0.45, similarity: 0.25,
                                      diversity: 0.20, wishlist: 0.10)

        /// Similarity dominates, diversity is almost switched off.
        static let similarToRecent = Weights(preference: 0.20, similarity: 0.65,
                                             diversity: 0.05, wishlist: 0.10)

        /// Diversity dominates, similarity is almost switched off.
        static let exploreNew = Weights(preference: 0.20, similarity: 0.05,
                                        diversity: 0.65, wishlist: 0.10)
    }

    /// Exponents and blend factors that reshape the raw components per mode.
    ///
    /// An exponent below `1.0` lifts mid-range values (the component "fires" more easily), an
    /// exponent above `1.0` pushes them down. Both keep `0...1` mapped onto `0...1`.
    private enum Shaping {

        /// Lifts mid-range similarity in ``RecommendationMode/similarToRecent``.
        static let similarModeSimilarityExponent = 0.55

        /// Damps diversity in ``RecommendationMode/similarToRecent``.
        static let similarModeDiversityExponent = 1.35

        /// Lifts mid-range diversity in ``RecommendationMode/exploreNew``.
        static let exploreModeDiversityExponent = 0.55

        /// Pushes similarity down in ``RecommendationMode/exploreNew``.
        static let exploreModeSimilarityExponent = 1.65

        /// Share of the shaped diversity component in the explore-mode blend.
        /// Together with ``exploreModeRareContinentShare`` this sums to `1.0`, so the blend stays
        /// inside `0...1`.
        static let exploreModeDiversityShare = 0.85

        /// Share of the rare-continent bonus in the explore-mode blend.
        static let exploreModeRareContinentShare = 0.15
    }

    /// Thresholds and sizes used while building the individual components.
    private enum Scoring {

        /// Neutral preference score used when ``UserPreferences`` holds no usable criterion at all.
        /// Without it every candidate would score `0` on this component and the ranking would go flat.
        static let neutralPreferenceScore = 0.35

        /// Number of most recently visited countries the similarity component compares against.
        static let recentVisitedLimit = 3

        /// Number of strongest wishlist travel tags that form the wishlist taste profile.
        static let topWishlistTravelTagCount = 4

        /// Number of strongest wishlist climate tags that form the wishlist taste profile.
        static let topWishlistClimateTagCount = 2

        /// Bucket for countries without a continent, so they still take part in the diversity share.
        static let unknownContinent = "Unknown"
    }

    // MARK: - Public API

    /// Scores every eligible country and returns the `topN` best matches.
    ///
    /// Candidates are filtered before scoring: countries the user already marked as
    /// ``CountryStatus/visited`` **or** ``CountryStatus/wishlist`` are excluded (the wishlist only
    /// feeds the taste profile), and the cost and safety limits from `preferences` act as hard
    /// filters. Because ``CostLevel`` and ``SafetyLevel`` are ranked with the lower raw value being
    /// cheaper and safer, a candidate is rejected when its raw value is *greater* than the limit.
    ///
    /// - Parameters:
    ///   - allCountries: Every known country, including the marked ones; the statuses on these
    ///     objects are what the filters and the wishlist profile read.
    ///   - trips: The user's trips, most recent first. Used for the similarity and diversity
    ///     components; when no trip carries countries, the visited countries stand in.
    ///   - preferences: The preferences to score against, including ``RecommendationMode``.
    ///   - topN: Maximum number of recommendations to return. Values below `0` yield an empty array.
    /// - Returns: At most `topN` recommendations, highest score first.
    /// - Note: Each component is `0...1` and the mode weights are normalised to sum to `1.0`, so
    ///   ``Recommendation/score`` is always in `0...1`. Equal scores break deterministically on
    ///   `iso2` ascending, so the same input always produces the same order.
    static func recommendTopCountries(
        allCountries: [Country],
        trips: [Trip],
        preferences: UserPreferences,
        topN: Int
    ) -> [Recommendation] {

        // Never recommend visited OR wishlisted countries (wishlist only influences taste)
        let visitedISO = Set(allCountries.filter { $0.status == .visited }.map(\.iso2))
        let wishlistISO = Set(allCountries.filter { $0.status == .wishlist }.map(\.iso2))

        let recentVisited = recentVisitedCountries(from: trips,
                                                  fallbackVisitedCountries: allCountries,
                                                  limit: Scoring.recentVisitedLimit)
        let continentShare = visitedContinentShare(from: trips,
                                                   fallbackVisitedCountries: allCountries)

        let wishlistProfile = WishlistProfile(from: allCountries.filter { $0.status == .wishlist })

        let candidates = allCountries.filter { country in
            guard !visitedISO.contains(country.iso2) else { return false }
            guard !wishlistISO.contains(country.iso2) else { return false }

            if let maxCost = preferences.maxCostLevel,
               country.costLevel.rawValue > maxCost.rawValue {
                return false
            }

            if let minSafety = preferences.minSafety,
               country.safetyLevel.rawValue > minSafety.rawValue {
                return false
            }

            return true
        }

        // Weights are normalized => sum to 1.0 so score can never exceed 1.0
        let weights = normalizedWeights(for: preferences.recommendationMode)

        let scored: [Recommendation] = candidates.map { country in
            // Raw components are each 0...1
            let prefRaw = preferenceMatchScore(country: country, preferences: preferences)
            let simRaw  = similarityToRecentScore(country: country, recentVisited: recentVisited)
            let divRaw  = diversityScore(country: country, visitedContinentShare: continentShare)
            let wishRaw = wishlistAffinityScore(country: country, wishlistProfile: wishlistProfile)

            // Mode shaping makes modes feel VERY different but keeps 0...1
            let shaped = shapedComponents(
                mode: preferences.recommendationMode,
                pref: prefRaw,
                sim: simRaw,
                div: divRaw,
                wish: wishRaw,
                country: country,
                continentShare: continentShare
            )

            // Weighted sum: because weights sum to 1 and each component is 0...1 => result in 0...1
            let score = clamp01(
                weights.preference * shaped.pref +
                weights.similarity * shaped.sim +
                weights.diversity * shaped.div +
                weights.wishlist * shaped.wish
            )

            let explanation = explanationText(
                for: country,
                mode: preferences.recommendationMode,
                pref: shaped.pref,
                sim: shaped.sim,
                div: shaped.div,
                wish: shaped.wish
            )

            return Recommendation(country: country, score: score, explanation: explanation)
        }

        // Stable sorting: score desc, then iso2 as final deterministic order
        let sorted = scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.country.iso2 < $1.country.iso2
        }

        return Array(sorted.prefix(max(0, topN)))
    }

    // MARK: - Weights

    /// The four component weights of a single scoring pass.
    private struct Weights {
        let preference: Double
        let similarity: Double
        let diversity: Double
        let wishlist: Double
    }

    /// The weights for `mode`, scaled so that they sum to `1.0`.
    ///
    /// - Parameter mode: The mode whose intent weights are used.
    /// - Returns: Normalised weights; a degenerate all-zero intent falls back to preference only.
    private static func normalizedWeights(for mode: RecommendationMode) -> Weights {
        // Intent weights (will be normalized)
        let raw: Weights = switch mode {
        case .balanced: ModeWeights.balanced
        case .similarToRecent: ModeWeights.similarToRecent
        case .exploreNew: ModeWeights.exploreNew
        }

        let sum = raw.preference + raw.similarity + raw.diversity + raw.wishlist
        guard sum > 0 else { return Weights(preference: 1, similarity: 0, diversity: 0, wishlist: 0) }

        return Weights(
            preference: raw.preference / sum,
            similarity: raw.similarity / sum,
            diversity: raw.diversity / sum,
            wishlist: raw.wishlist / sum
        )
    }

    // MARK: - Components (0...1)

    /// The four scoring components of one candidate, each clamped to `0...1`.
    private struct Components {
        var pref: Double
        var sim: Double
        var div: Double
        var wish: Double
    }

    /// Applies the mode-specific reshaping to the raw components.
    ///
    /// All transforms are monotonic on `0...1` and the explore-mode blend uses shares that sum to
    /// `1.0`, so every returned component stays inside `0...1`.
    ///
    /// - Parameters:
    ///   - mode: The mode whose emphasis is applied.
    ///   - pref: Raw preference match, `0...1`.
    ///   - sim: Raw similarity to recent trips, `0...1`.
    ///   - div: Raw continent diversity, `0...1`.
    ///   - wish: Raw wishlist affinity, `0...1`.
    ///   - country: The candidate, needed for the explore-mode rare-continent bonus.
    ///   - continentShare: Share of the user's history per continent, keyed by continent name.
    /// - Returns: The reshaped ``Components``.
    private static func shapedComponents(
        mode: RecommendationMode,
        pref: Double,
        sim: Double,
        div: Double,
        wish: Double,
        country: Country,
        continentShare: [String: Double]
    ) -> Components {

        var components = Components(pref: clamp01(pref), sim: clamp01(sim),
                                    div: clamp01(div), wish: clamp01(wish))

        switch mode {
        case .balanced:
            return components

        case .similarToRecent:
            // Boost similarity, damp diversity a bit.
            // These nonlinear transforms make the mode "feel" different.
            components.sim = clamp01(pow(components.sim, Shaping.similarModeSimilarityExponent))
            components.div = clamp01(pow(components.div, Shaping.similarModeDiversityExponent))
            return components

        case .exploreNew:
            // Boost diversity, penalize similarity.
            components.div = clamp01(pow(components.div, Shaping.exploreModeDiversityExponent))
            components.sim = clamp01(pow(components.sim, Shaping.exploreModeSimilarityExponent))

            // Extra push for underrepresented continents
            let continent = country.continent ?? Scoring.unknownContinent
            let share = clamp01(continentShare[continent, default: 0.0]) // 0..1
            let rareBonus = clamp01(1.0 - share)
            components.div = clamp01(
                Shaping.exploreModeDiversityShare * components.div +
                Shaping.exploreModeRareContinentShare * rareBonus
            )
            return components
        }
    }

    // MARK: - Score Functions (each 0...1)

    /// How well `country` matches the user's explicit preferences.
    ///
    /// Scored as hit points over the number of criteria the user actually set: one point per matching
    /// desired travel tag, one for any matching climate tag, one for a travel style that fits the
    /// preferred trip duration.
    ///
    /// - Parameters:
    ///   - country: The candidate to score.
    ///   - preferences: The preferences to match against.
    /// - Returns: `0...1`, or ``Scoring/neutralPreferenceScore`` when no criterion is set at all.
    private static func preferenceMatchScore(country: Country, preferences: UserPreferences) -> Double {
        var points = 0.0
        var maxPoints = 0.0

        if !preferences.desiredTags.isEmpty {
            maxPoints += Double(preferences.desiredTags.count)
            let tags = Set(country.travelTags)
            for tag in preferences.desiredTags where tags.contains(tag) { points += 1 }
        }

        if !preferences.preferredClimate.isEmpty {
            maxPoints += 1
            let climates = Set(country.climateTags)
            if preferences.preferredClimate.contains(where: { climates.contains($0) }) {
                points += 1
            }
        }

        if let duration = preferences.preferredDuration {
            maxPoints += 1
            let tags = Set(country.travelTags)
            let match: Bool = switch duration {
            case .weekend, .short:
                tags.contains(.citytrip) || tags.contains(.culture) || tags.contains(.nightlife)
            case .medium:
                true
            case .long, .nomad:
                tags.contains(.nature) || tags.contains(.adventure)
                    || tags.contains(.relax) || tags.contains(.hiking)
            }
            if match { points += 1 }
        }

        // Avoid an all-zero flat ranking when the user set no criteria at all.
        guard maxPoints > 0 else { return Scoring.neutralPreferenceScore }
        return clamp01(points / maxPoints)
    }

    /// How similar `country` is to the most recently visited countries.
    ///
    /// Compares tag signatures (travel plus climate tags) with the Jaccard index and keeps the best
    /// match, so a single strong resemblance is enough.
    ///
    /// - Parameters:
    ///   - country: The candidate to score.
    ///   - recentVisited: The reference countries, as returned by
    ///     ``recentVisitedCountries(from:fallbackVisitedCountries:limit:)``.
    /// - Returns: `0...1`; `0` when there is no history to compare against.
    private static func similarityToRecentScore(country: Country, recentVisited: [Country]) -> Double {
        guard !recentVisited.isEmpty else { return 0.0 }

        // Use travel+climate tags for more variance (less ties)
        let target = tagSignature(for: country)

        let best = recentVisited
            .map { jaccard(target, tagSignature(for: $0)) }
            .max() ?? 0.0

        return clamp01(best)
    }

    /// How under-represented the continent of `country` is in the user's history.
    ///
    /// - Parameters:
    ///   - country: The candidate to score.
    ///   - visitedContinentShare: Share of the history per continent, summing to `1.0`.
    /// - Returns: `0...1`; `1` for a continent the user has never been to.
    private static func diversityScore(country: Country, visitedContinentShare: [String: Double]) -> Double {
        let continent = country.continent ?? Scoring.unknownContinent
        let share = clamp01(visitedContinentShare[continent, default: 0.0])
        return clamp01(1.0 - share)
    }

    /// How well `country` matches the taste expressed by the wishlist.
    ///
    /// Scores one point for overlapping with the strongest wishlist travel tags and one for the
    /// strongest wishlist climate tags.
    ///
    /// - Parameters:
    ///   - country: The candidate to score.
    ///   - wishlistProfile: Tag frequencies across the wishlisted countries.
    /// - Returns: `0...1`; `0` when the wishlist carries no tags.
    private static func wishlistAffinityScore(country: Country, wishlistProfile: WishlistProfile) -> Double {
        guard !wishlistProfile.travelTags.isEmpty || !wishlistProfile.climateTags.isEmpty else { return 0.0 }

        var points = 0.0
        var maxPoints = 0.0

        let topWishTravel = Set(wishlistProfile.travelTags
            .sorted { $0.value > $1.value }
            .prefix(Scoring.topWishlistTravelTagCount)
            .map(\.key)
        )

        if !topWishTravel.isEmpty {
            maxPoints += 1
            if country.travelTags.contains(where: { topWishTravel.contains($0) }) { points += 1 }
        }

        let topWishClimate = Set(wishlistProfile.climateTags
            .sorted { $0.value > $1.value }
            .prefix(Scoring.topWishlistClimateTagCount)
            .map(\.key)
        )

        if !topWishClimate.isEmpty {
            maxPoints += 1
            if country.climateTags.contains(where: { topWishClimate.contains($0) }) { points += 1 }
        }

        guard maxPoints > 0 else { return 0.0 }
        return clamp01(points / maxPoints)
    }

    // MARK: - Explainability

    /// Builds the user-facing reason for a recommendation.
    ///
    /// Names the active mode and the strongest of the four shaped components; when preference match
    /// wins, the country's own travel tags are named instead of the component.
    ///
    /// - Parameters:
    ///   - country: The recommended country.
    ///   - mode: The active mode, used as the label prefix.
    ///   - pref: Shaped preference match, `0...1`.
    ///   - sim: Shaped similarity, `0...1`.
    ///   - div: Shaped diversity, `0...1`.
    ///   - wish: Shaped wishlist affinity, `0...1`.
    /// - Returns: A short single-line explanation.
    private static func explanationText(
        for country: Country,
        mode: RecommendationMode,
        pref: Double,
        sim: Double,
        div: Double,
        wish: Double
    ) -> String {

        let modeLabel: String = switch mode {
        case .balanced: "Balanced"
        case .similarToRecent: "Similar"
        case .exploreNew: "Explore"
        }

        let best = max(pref, sim, div, wish)

        if best == sim { return "\(modeLabel) • Similar to your recent trips" }
        if best == div { return "\(modeLabel) • Boosted for travel diversity" }
        if best == wish { return "\(modeLabel) • Matches your wishlist taste" }

        let tags = country.travelTags.prefix(2).map(\.rawValue)
        return tags.isEmpty ? "\(modeLabel) • Matches your preferences"
                            : "\(modeLabel) • Matches: \(tags.joined(separator: ", "))"
    }

    // MARK: - History Helpers

    /// The most recently visited countries, or, while no trips are recorded,
    /// every visited country, so similarity scoring still has something to work with.
    ///
    /// - Parameters:
    ///   - trips: The user's trips, most recent first.
    ///   - fallbackVisitedCountries: Country list the visited fallback is taken from.
    ///   - limit: Maximum number of countries collected from the trips.
    /// - Returns: Up to `limit` distinct countries from the trips, otherwise every visited country.
    private static func recentVisitedCountries(from trips: [Trip],
                                               fallbackVisitedCountries: [Country],
                                               limit: Int) -> [Country] {
        var unique: [Country] = []
        for trip in trips {
            for country in trip.countries {
                if !unique.contains(where: { $0.iso2 == country.iso2 }) {
                    unique.append(country)
                    if unique.count == limit { return unique }
                }
            }
        }

        guard unique.isEmpty else { return unique }

        return fallbackVisitedCountries.filter { $0.status == .visited }
    }

    /// The share of the user's history that falls on each continent.
    ///
    /// Counts the countries of every trip; when no trip carries countries, the visited countries are
    /// counted instead, so the diversity component works before the first trip is logged.
    ///
    /// - Parameters:
    ///   - trips: The user's trips.
    ///   - fallbackVisitedCountries: Country list the visited fallback is taken from.
    /// - Returns: Continent name to share in `0...1`, summing to `1.0`; empty when nothing is known.
    private static func visitedContinentShare(from trips: [Trip],
                                              fallbackVisitedCountries: [Country]) -> [String: Double] {
        var counts: [String: Int] = [:]
        var total = 0

        let hasTrips = trips.contains(where: { !$0.countries.isEmpty })
        if hasTrips {
            for trip in trips {
                for country in trip.countries {
                    let continent = country.continent ?? Scoring.unknownContinent
                    counts[continent, default: 0] += 1
                    total += 1
                }
            }
        } else {
            let visited = fallbackVisitedCountries.filter { $0.status == .visited }
            for country in visited {
                let continent = country.continent ?? Scoring.unknownContinent
                counts[continent, default: 0] += 1
                total += 1
            }
        }

        guard total > 0 else { return [:] }
        return counts.mapValues { Double($0) / Double(total) }
    }

    // MARK: - Wishlist Profile

    /// Tag frequencies across the wishlisted countries, used as a taste profile.
    private struct WishlistProfile {

        /// How often each travel tag appears on the wishlist.
        let travelTags: [TravelTag: Int]

        /// How often each climate tag appears on the wishlist.
        let climateTags: [ClimateTag: Int]

        /// Counts the tags of `countries`.
        ///
        /// - Parameter countries: The wishlisted countries.
        init(from countries: [Country]) {
            var travel: [TravelTag: Int] = [:]
            var climate: [ClimateTag: Int] = [:]

            for country in countries {
                for tag in country.travelTags { travel[tag, default: 0] += 1 }
                for tag in country.climateTags { climate[tag, default: 0] += 1 }
            }

            self.travelTags = travel
            self.climateTags = climate
        }
    }

    // MARK: - Utilities

    /// Clamps `value` into `0...1`, the range every component and the final score must stay in.
    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    /// The comparable tag signature of a country.
    ///
    /// Travel and climate tags are prefixed so the two namespaces cannot collide.
    ///
    /// - Parameter country: The country to describe.
    /// - Returns: A set of prefixed tag identifiers.
    private static func tagSignature(for country: Country) -> Set<String> {
        // Use both travel + climate tags for better discrimination
        let travel = country.travelTags.map { "t:\($0.rawValue)" }
        let climate = country.climateTags.map { "c:\($0.rawValue)" }
        return Set(travel + climate)
    }

    /// The Jaccard index of two sets: intersection over union.
    ///
    /// - Parameters:
    ///   - lhs: First set.
    ///   - rhs: Second set.
    /// - Returns: `0...1`; `0` when both sets are empty.
    private static func jaccard<T: Hashable>(_ lhs: Set<T>, _ rhs: Set<T>) -> Double {
        let unionCount = lhs.union(rhs).count
        guard unionCount > 0 else { return 0.0 }
        return Double(lhs.intersection(rhs).count) / Double(unionCount)
    }

}
