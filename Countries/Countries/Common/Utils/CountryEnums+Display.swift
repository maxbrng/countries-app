//
//  CountryEnums+Display.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI

// The enums themselves live in the data layer and stay free of SwiftUI. Their user-facing
// names belong here, so a raw case never reaches the screen through `String(describing:)`.

extension TravelTag {

    /// Name shown to the user, looked up in the string catalog.
    var title: LocalizedStringKey {
        switch self {
        case .beach: "Beach"
        case .nature: "Nature"
        case .hiking: "Hiking"
        case .culture: "Culture"
        case .food: "Food"
        case .nightlife: "Nightlife"
        case .citytrip: "City trip"
        case .relax: "Relax"
        case .adventure: "Adventure"
        case .skiing: "Skiing"
        }
    }

    /// SF Symbol representing the tag, on a filter chip and on a country card.
    var symbolName: String {
        switch self {
        case .beach: "sun.max"
        case .nature: "leaf"
        case .hiking: "figure.hiking"
        case .culture: "building.columns"
        case .food: "fork.knife"
        case .nightlife: "sparkles"
        case .citytrip: "building.2"
        case .relax: "bed.double"
        case .adventure: "mountain.2"
        case .skiing: "snowflake"
        }
    }
}

extension ClimateTag {

    /// Name shown to the user, looked up in the string catalog.
    var title: LocalizedStringKey {
        switch self {
        case .cold: "Cold"
        case .mild: "Mild"
        case .warm: "Warm"
        case .tropical: "Tropical"
        case .mixed: "Mixed"
        }
    }
}

extension CostLevel {

    /// Name shown to the user, looked up in the string catalog.
    ///
    /// - Note: Lower is cheaper, which is why the order reads from very cheap upwards.
    var title: LocalizedStringKey {
        switch self {
        case .veryCheap: "Very cheap"
        case .cheap: "Cheap"
        case .medium: "Moderate"
        case .expensive: "Expensive"
        case .veryExpensive: "Very expensive"
        }
    }
}

extension SafetyLevel {

    /// Name shown to the user, looked up in the string catalog.
    ///
    /// - Note: Lower is safer.
    var title: LocalizedStringKey {
        switch self {
        case .verySafe: "Very safe"
        case .safe: "Safe"
        case .mixed: "Mixed"
        case .risky: "Risky"
        case .veryRisky: "Very risky"
        }
    }
}
