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

    /// Short form for a chip that has to fit beside a symbol in a flow layout.
    ///
    /// Only differs from ``title`` where the full name is too long for a chip; the other
    /// cases share the key, so a translator sees each word once.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .hiking: "Hike"
        case .nightlife: "Night"
        case .citytrip: "City"
        case .skiing: "Ski"
        default: title
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
        // Explicit key: "mixed" is "gemischt" for a climate and "durchwachsen" for a safety
        // level, and one source string cannot hold both.
        case .mixed: "climate.mixed"
        }
    }

    /// Short form for the card's thermometer badge. Identical to ``title`` today, kept as its
    /// own property so the badge can shorten a name without touching the filter chips.
    var shortTitle: LocalizedStringKey { title }
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
        // See ``ClimateTag/title``: the same English word, a different German one.
        case .mixed: "safety.mixed"
        case .risky: "Risky"
        case .veryRisky: "Very risky"
        }
    }

    /// Short form for the card's mini chip. Identical to ``title`` today.
    var shortTitle: LocalizedStringKey { title }
}
