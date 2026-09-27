//
//  Country+Enums.swift
//  Countries
//
//  Created by Max Breuning on 19.01.26.
//

import Foundation

enum CountryStatus: Int, Codable, CaseIterable {
    case none = 0
    case visited = 1
    case wishlist = 2
}

enum TravelTag: String, Codable, CaseIterable {
    case beach, nature, hiking, culture, food, nightlife, citytrip, relax, adventure, skiing
}

enum ClimateTag: String, Codable, CaseIterable {
    case cold, mild, warm, tropical, mixed
}

enum CostLevel: Int, Codable, CaseIterable {
    case veryCheap = 1
    case cheap = 2
    case medium = 3
    case expensive = 4
    case veryExpensive = 5
}

enum SafetyLevel: Int, Codable, CaseIterable {
    case verySafe = 1
    case safe = 2
    case mixed = 3
    case risky = 4
    case veryRisky = 5
}
