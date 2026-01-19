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

enum TravelDuration: Int, Codable, CaseIterable {
    case weekend = 1          // 1–3 days
    case short = 2            // 4–7 days
    case medium = 3           // 8–14 days
    case long = 4             // 15–30 days
    case nomad = 5            // 30+ days
}

enum Season: Int, Codable, CaseIterable {
    case spring = 1
    case summer = 2
    case autumn = 3
    case winter = 4

    static func from(date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}
