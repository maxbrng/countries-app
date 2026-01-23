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
    
    @Attribute(.unique)
    var profileKey: Int   // 1,2,3 (mock user id)
    
    var desiredTags: [TravelTag]          // same enum as in Country
    var preferredClimate: [ClimateTag]    // allow multiple
    var maxCostLevel: CostLevel?          // budget constraint
    var minSafety: SafetyLevel?           // e.g. at least "safe"
    
    var preferredDuration: TravelDuration?
    var preferredSeason: Season?          // if user plans next trip seasonally
    
    var recommendationMode: RecommendationMode
    
    var userDidCustomize: Bool
    var updatedAt: Date
    
    init(profileKey: Int,
         desiredTags: [TravelTag] = [],
         preferredClimate: [ClimateTag] = [],
         maxCostLevel: CostLevel? = nil,
         minSafety: SafetyLevel? = nil,
         preferredDuration: TravelDuration? = nil,
         preferredSeason: Season? = nil,
         recommendationMode: RecommendationMode = .balanced,
         userDidCustomize: Bool = false,
         updatedAt: Date = .now) {
        
        self.profileKey = profileKey
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

enum RecommendationMode: String, Codable {
    case balanced
    case similarToRecent
    case exploreNew
}
