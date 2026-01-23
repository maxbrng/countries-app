//
//  RecommendationService.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//
//  Explainable recommendations based on:
//  - User preferences (structured context)
//  - Travel history (trips / visited)
//  - Country attributes (tags, climate, cost, safety, continent)
//

import Foundation

enum RecommendationService {

    // MARK: - Public Types

    struct Recommendation: Identifiable {
        let id = UUID()
        let country: Country
        /// Always clamped to 0...1
        let score: Double
        let explanation: String
    }

    // MARK: - Public API

    static func recommendTopCountries(
        allCountries: [Country],
        trips: [Trip],
        preferences: UserPreferences,
        topN: Int
    ) -> [Recommendation] {

        // Never recommend visited OR wishlisted countries (wishlist only influences taste)
        let visitedISO = Set(allCountries.filter { $0.status == .visited }.map(\.iso2))
        let wishlistISO = Set(allCountries.filter { $0.status == .wishlist }.map(\.iso2))

        let recentVisited = recentVisitedCountries(from: trips, limit: 3)
        let continentShare = visitedContinentShare(from: trips, fallbackVisitedCountries: allCountries)

        let wishlistProfile = WishlistProfile(from: allCountries.filter { $0.status == .wishlist })

        let candidates = allCountries.filter { country in
            guard !visitedISO.contains(country.iso2) else { return false }
            guard !wishlistISO.contains(country.iso2) else { return false }

            if let maxCost = preferences.maxCostLevel,
               country.costLevel.rawValue > maxCost.rawValue { return false }

            if let minSafety = preferences.minSafety,
               country.safetyLevel.rawValue > minSafety.rawValue { return false }

            return true
        }

        // Weights are normalized => sum to 1.0 so score can never exceed 1.0
        let weights = normalizedWeights(for: preferences.recommendationMode)

        // Deterministic tie-breaker seed that changes whenever user hits Done (you update updatedAt there)
        let seed = preferences.updatedAt.timeIntervalSince1970

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
            var score =
                weights.preference * shaped.pref +
                weights.similarity * shaped.sim +
                weights.diversity * shaped.div +
                weights.wishlist * shaped.wish

            // Add a tiny deterministic jitter so equal scores basically never happen.
            // Still clamp to guarantee 0...1.
            score = clamp01(score + deterministicJitter(seed: seed, key: country.iso2) * 1e-9)

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

    private struct Weights {
        let preference: Double
        let similarity: Double
        let diversity: Double
        let wishlist: Double
    }

    private static func normalizedWeights(for mode: RecommendationMode) -> Weights {
        // Intent weights (will be normalized)
        let raw: Weights = switch mode {
        case .balanced:
            Weights(preference: 0.45, similarity: 0.25, diversity: 0.20, wishlist: 0.10)
        case .similarToRecent:
            Weights(preference: 0.20, similarity: 0.65, diversity: 0.05, wishlist: 0.10)
        case .exploreNew:
            Weights(preference: 0.20, similarity: 0.05, diversity: 0.65, wishlist: 0.10)
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

    private struct Components {
        var pref: Double
        var sim: Double
        var div: Double
        var wish: Double
    }

    private static func shapedComponents(
        mode: RecommendationMode,
        pref: Double,
        sim: Double,
        div: Double,
        wish: Double,
        country: Country,
        continentShare: [String: Double]
    ) -> Components {

        var c = Components(pref: clamp01(pref), sim: clamp01(sim), div: clamp01(div), wish: clamp01(wish))

        switch mode {
        case .balanced:
            return c

        case .similarToRecent:
            // Boost similarity, damp diversity a bit.
            // These nonlinear transforms make the mode “feel” different.
            c.sim = clamp01(pow(c.sim, 0.55))     // boost mid sims
            c.div = clamp01(pow(c.div, 1.35))     // suppress diversity a bit
            return c

        case .exploreNew:
            // Boost diversity, penalize similarity.
            c.div = clamp01(pow(c.div, 0.55))     // boost mid diversity
            c.sim = clamp01(pow(c.sim, 1.65))     // push similarity down

            // Extra push for underrepresented continents
            let cont = country.continent ?? "Unknown"
            let share = clamp01(continentShare[cont, default: 0.0]) // 0..1
            let rareBonus = clamp01(1.0 - share)
            c.div = clamp01(0.85 * c.div + 0.15 * rareBonus)
            return c
        }
    }

    // MARK: - Score Functions (each 0...1)

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
                tags.contains(.nature) || tags.contains(.adventure) || tags.contains(.relax) || tags.contains(.hiking)
            }
            if match { points += 1 }
        }

        guard maxPoints > 0 else { return 0.35 } // avoid all-zero flat ranking
        return clamp01(points / maxPoints)
    }

    private static func similarityToRecentScore(country: Country, recentVisited: [Country]) -> Double {
        guard !recentVisited.isEmpty else { return 0.0 }

        // Use travel+climate tags for more variance (less ties)
        let target = tagSignature(for: country)

        let best = recentVisited
            .map { jaccard(target, tagSignature(for: $0)) }
            .max() ?? 0.0

        return clamp01(best)
    }

    private static func diversityScore(country: Country, visitedContinentShare: [String: Double]) -> Double {
        let cont = country.continent ?? "Unknown"
        let share = clamp01(visitedContinentShare[cont, default: 0.0])
        return clamp01(1.0 - share)
    }

    private static func wishlistAffinityScore(country: Country, wishlistProfile: WishlistProfile) -> Double {
        guard !wishlistProfile.travelTags.isEmpty || !wishlistProfile.climateTags.isEmpty else { return 0.0 }

        var points = 0.0
        var maxPoints = 0.0

        let topWishTravel = Set(wishlistProfile.travelTags
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map(\.key)
        )

        if !topWishTravel.isEmpty {
            maxPoints += 1
            if country.travelTags.contains(where: { topWishTravel.contains($0) }) { points += 1 }
        }

        let topWishClimate = Set(wishlistProfile.climateTags
            .sorted { $0.value > $1.value }
            .prefix(2)
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

    private static func recentVisitedCountries(from trips: [Trip], limit: Int) -> [Country] {
        var unique: [Country] = []
        for trip in trips {
            for country in trip.countries {
                if !unique.contains(where: { $0.iso2 == country.iso2 }) {
                    unique.append(country)
                    if unique.count == limit { return unique }
                }
            }
        }
        return unique
    }

    private static func visitedContinentShare(from trips: [Trip], fallbackVisitedCountries: [Country]) -> [String: Double] {
        var counts: [String: Int] = [:]
        var total = 0

        let hasTrips = trips.contains(where: { !$0.countries.isEmpty })
        if hasTrips {
            for trip in trips {
                for country in trip.countries {
                    let cont = country.continent ?? "Unknown"
                    counts[cont, default: 0] += 1
                    total += 1
                }
            }
        } else {
            let visited = fallbackVisitedCountries.filter { $0.status == .visited }
            for country in visited {
                let cont = country.continent ?? "Unknown"
                counts[cont, default: 0] += 1
                total += 1
            }
        }

        guard total > 0 else { return [:] }
        return counts.mapValues { Double($0) / Double(total) }
    }

    // MARK: - Wishlist Profile

    private struct WishlistProfile {
        let travelTags: [TravelTag: Int]
        let climateTags: [ClimateTag: Int]

        init(from countries: [Country]) {
            var t: [TravelTag: Int] = [:]
            var c: [ClimateTag: Int] = [:]

            for country in countries {
                for tag in country.travelTags { t[tag, default: 0] += 1 }
                for tag in country.climateTags { c[tag, default: 0] += 1 }
            }

            self.travelTags = t
            self.climateTags = c
        }
    }

    // MARK: - Utilities

    private static func clamp01(_ x: Double) -> Double {
        min(1.0, max(0.0, x))
    }

    private static func tagSignature(for country: Country) -> Set<String> {
        // Use both travel + climate tags for better discrimination
        let travel = country.travelTags.map { "t:\($0.rawValue)" }
        let climate = country.climateTags.map { "c:\($0.rawValue)" }
        return Set(travel + climate)
    }

    private static func jaccard<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Double {
        let unionCount = a.union(b).count
        guard unionCount > 0 else { return 0.0 }
        return Double(a.intersection(b).count) / Double(unionCount)
    }

    /// Deterministic tiny number in 0...1 (changes when seed changes)
    private static func deterministicJitter(seed: Double, key: String) -> Double {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(Int(seed))
        let h = hasher.finalize()
        return Double(UInt(bitPattern: h)) / Double(UInt.max)
    }
}
