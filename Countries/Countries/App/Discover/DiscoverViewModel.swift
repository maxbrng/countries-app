//
//  DiscoverViewModel.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import Combine

struct CountryRecommendation: Identifiable, Hashable {
    
    let id: UUID
    let name: String
    let subtitle: String
    let emoji: String
    let gradient: [Color]
    
    init(id: UUID = UUID(), name: String, subtitle: String, emoji: String, gradient: [Color]) {
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
