//
//  PreferenceDerivationService.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//
//  Derives sensible default preferences from the user's travel history.
//  Works fully offline.
//

import Foundation

enum PreferenceDerivationService {
    
    struct AutoPreferences {
        var desiredTags: [TravelTag]
        var preferredClimate: [ClimateTag]
        var maxCostLevel: CostLevel?
        var minSafety: SafetyLevel?
        var preferredDuration: TravelDuration?
        var preferredSeason: Season?
    }
    
    // MARK: - Public API
    
    static func derive(
        visitedCountries: [Country],
        wishlistedCountries: [Country],
        trips: [Trip]
    ) -> AutoPreferences {
        
        // Gewichtung: visited zählt stärker als wishlist
        let weightedCountries =
        visitedCountries +
        visitedCountries +        // visited x2
        wishlistedCountries       // wishlist x1
        
        return AutoPreferences(
            desiredTags: topTravelTags(from: weightedCountries, take: 4),
            preferredClimate: topClimateTags(from: weightedCountries, take: 2),
            maxCostLevel: derivedMaxCostLevel(from: weightedCountries),
            minSafety: derivedMinSafetyLevel(from: weightedCountries),
            preferredDuration: mostCommonTripDuration(from: trips),
            preferredSeason: mostCommonTripSeason(from: trips)
        )
    }
    
    // MARK: - Tags
    
    private static func topTravelTags(from countries: [Country], take: Int) -> [TravelTag] {
        guard countries.count >= 2 else { return [] }
        
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
    
    private static func topClimateTags(from countries: [Country], take: Int) -> [ClimateTag] {
        guard countries.count >= 2 else { return [] }
        
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
    
    // MARK: - Cost & Safety (IMPORTANT PART)
    
    /// Max cost should be tolerant → never too low
    private static func derivedMaxCostLevel(from countries: [Country]) -> CostLevel? {
        let values = countries.map { $0.costLevel.rawValue }.sorted()
        guard values.count >= 3 else { return nil }
        
        let median = values[values.count / 2]
        
        // Bias UPWARDS by +1 (but clamp)
        let biased = min(median + 1, CostLevel.allCases.last!.rawValue)
        return CostLevel(rawValue: biased)
    }
    
    /// Min safety should be realistic → never too strict
    private static func derivedMinSafetyLevel(from countries: [Country]) -> SafetyLevel? {
        let values = countries.map { $0.safetyLevel.rawValue }.sorted()
        guard values.count >= 3 else { return nil }
        
        let median = values[values.count / 2]
        
        // Bias DOWNWARDS by -1 (but clamp)
        let biased = max(median - 1, SafetyLevel.allCases.first!.rawValue)
        return SafetyLevel(rawValue: biased)
    }
    
    // MARK: - Trips
    
    private static func mostCommonTripDuration(from trips: [Trip]) -> TravelDuration? {
        guard trips.count >= 2 else { return nil }
        
        var counts: [TravelDuration: Int] = [:]
        for trip in trips {
            if let duration = trip.duration {
                counts[duration, default: 0] += 1
            }
        }
        
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    private static func mostCommonTripSeason(from trips: [Trip]) -> Season? {
        guard trips.count >= 2 else { return nil }
        
        var counts: [Season: Int] = [:]
        for trip in trips {
            if let season = trip.season {
                counts[season, default: 0] += 1
            }
        }
        
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
