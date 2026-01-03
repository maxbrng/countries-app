//
//  DiscoverViewModel.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import Combine

public struct CountryRecommendation: Identifiable, Hashable {
    
    public let id: UUID
    public let name: String
    public let subtitle: String
    public let emoji: String
    public let gradient: [Color]
    
    public init(id: UUID = UUID(), name: String, subtitle: String, emoji: String, gradient: [Color]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.emoji = emoji
        self.gradient = gradient
    }
}

final class DiscoverViewModel: ObservableObject {
    
    @Published var items: [CountryRecommendation] = []
    
    init() {
        loadDemo()
    }
    
    func loadDemo() {
        self.items = [
            .init(name: "Japan", subtitle: "Food, Culture, Cities", emoji: "🇯🇵", gradient: [.purple, .pink]),
            .init(name: "Norway", subtitle: "Fjords & Northern Lights", emoji: "🇳🇴", gradient: [.blue, .cyan]),
            .init(name: "Portugal", subtitle: "Surf & Sun", emoji: "🇵🇹", gradient: [.orange, .red]),
            .init(name: "Iceland", subtitle: "Volcanoes & Hot Springs", emoji: "🇮🇸", gradient: [.teal, .indigo])
        ]
    }
}
