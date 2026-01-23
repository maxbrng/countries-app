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

    static func derive(from visitedCountries: [Country], trips: [Trip]) -> AutoPreferences {
        AutoPreferences(
            desiredTags: topTravelTags(from: visitedCountries, take: 4),
            preferredClimate: topClimateTags(from: visitedCountries, take: 2),
            maxCostLevel: medianCostLevel(from: visitedCountries),
            minSafety: medianSafetyLevel(from: visitedCountries),
            preferredDuration: mostCommonTripDuration(from: trips),
            preferredSeason: mostCommonTripSeason(from: trips)
        )
    }

    private static func topTravelTags(from countries: [Country], take: Int) -> [TravelTag] {
        
        var counts: [TravelTag: Int] = [:]
        
        for country in countries {
            for tag in country.travelTags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(take).map(\.key)
    }

    private static func topClimateTags(from countries: [Country], take: Int) -> [ClimateTag] {
        
        var counts: [ClimateTag: Int] = [:]
        
        for country in countries {
            for tag in country.climateTags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(take).map(\.key)
    }

    private static func medianCostLevel(from countries: [Country]) -> CostLevel? {
        
        let values = countries.map { $0.costLevel.rawValue }.sorted()
        
        guard !values.isEmpty else { return nil }
        
        return CostLevel(rawValue: values[values.count / 2])
    }

    private static func medianSafetyLevel(from countries: [Country]) -> SafetyLevel? {
        
        let values = countries.map { $0.safetyLevel.rawValue }.sorted()
        
        guard !values.isEmpty else { return nil }
        
        return SafetyLevel(rawValue: values[values.count / 2])
    }

    private static func mostCommonTripDuration(from trips: [Trip]) -> TravelDuration? {
        
        var counts: [TravelDuration: Int] = [:]
        
        for trip in trips {
            if let duration = trip.duration {
                counts[duration, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func mostCommonTripSeason(from trips: [Trip]) -> Season? {
        
        var counts: [Season: Int] = [:]
        
        for trip in trips {
            if let season = trip.season {
                counts[season, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
