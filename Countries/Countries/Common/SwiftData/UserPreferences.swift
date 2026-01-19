//
//  UserPreferences.swift
//  Countries
//
//  Created by Max Breuning on 19.01.26.
//

import SwiftData
import Foundation

@Model
final class UserPreferences {
    var desiredTags: [TravelTag]          // same enum as in Country
    var preferredClimate: [ClimateTag]    // allow multiple
    var maxCostLevel: CostLevel?          // budget constraint
    var minSafety: SafetyLevel?           // e.g. at least "safe"

    var preferredDuration: TravelDuration?
    var preferredSeason: Season?          // if user plans next trip seasonally

    var recommendationMode: RecommendationMode
    var updatedAt: Date

    init(
        desiredTags: [TravelTag] = [],
        preferredClimate: [ClimateTag] = [],
        maxCostLevel: CostLevel? = nil,
        minSafety: SafetyLevel? = nil,
        preferredDuration: TravelDuration? = nil,
        preferredSeason: Season? = nil,
        recommendationMode: RecommendationMode = .balanced,
        updatedAt: Date = .now
    ) {
        self.desiredTags = desiredTags
        self.preferredClimate = preferredClimate
        self.maxCostLevel = maxCostLevel
        self.minSafety = minSafety
        self.preferredDuration = preferredDuration
        self.preferredSeason = preferredSeason
        self.recommendationMode = recommendationMode
        self.updatedAt = updatedAt
    }
}

enum RecommendationMode: String, Codable {
    case balanced
    case similarToRecent
    case exploreNew
}
