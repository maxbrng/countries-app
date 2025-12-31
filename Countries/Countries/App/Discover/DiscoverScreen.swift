//
//  DiscoverScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit

struct DiscoverScreen: View {
    
    @Binding var path: NavigationPath
    
    let items: [CountryRecommendation] = demoCountries
    
    var body: some View {
        
        GeometryReader { geo in
            let cardHeight = geo.size.height - 40
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: 0) {

                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            
                            CountryCardView(item: item, height: cardHeight)
                                .containerRelativeFrame(.vertical, count: 1, spacing: 0)
                                .visualEffect { content, proxy in
                                    let frame = proxy.frame(in: .scrollView)
                                    let bounds = proxy.bounds(of: .scrollView)
                                    let center = bounds?.midY ?? 0
                                    let distance = abs(frame.midY - center)
                                    let maxDistance = (bounds?.height ?? 1) / 2
                                    let progress = min(distance / maxDistance, 1)
                                    let scale = 1.0 - (0.05 * progress)
                                    let opacity = 1.0 - (0.25 * progress)
                                    return content
                                        .scaleEffect(scale, anchor: .center)
                                        .opacity(opacity)
                                }
                        }
                        .buttonStyle(.plain)
                        .scrollTargetLayout()
                    }
                    
                }
                .padding(.horizontal, 16)
            }
            
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CountryRecommendation.self) { item in
            CountryDetailView(item: item)
        }
    }
}

struct CountryRecommendation: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let emoji: String
    let gradient: [Color]
}

// MARK: - Demo Data

let demoCountries: [CountryRecommendation] = [
    .init(name: "Japan", subtitle: "Food, Culture, Cities", emoji: "🇯🇵", gradient: [.purple, .pink]),
    .init(name: "Norwegen", subtitle: "Fjorde & Nordlichter", emoji: "🇳🇴", gradient: [.blue, .cyan]),
    .init(name: "Portugal", subtitle: "Surf & Sonne", emoji: "🇵🇹", gradient: [.orange, .red]),
    .init(name: "Island", subtitle: "Vulkane & Hot Springs", emoji: "🇮🇸", gradient: [.teal, .indigo]),
    .init(name: "Island", subtitle: "Vulkane & Hot Springs", emoji: "🇮🇸", gradient: [.teal, .indigo]),
    .init(name: "Island", subtitle: "Vulkane & Hot Springs", emoji: "🇮🇸", gradient: [.teal, .indigo]),
    .init(name: "Island", subtitle: "Vulkane & Hot Springs", emoji: "🇮🇸", gradient: [.teal, .indigo])
]

// MARK: - Card

struct CountryCardView: View {
    let item: CountryRecommendation
    let height: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(item.emoji)
                        .font(.system(size: 40))
                    Text(item.name)
                        .font(.title.bold())
                }
                
                Text(item.subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer(minLength: 0)
                
                HStack {
                    Text("Tap für Details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(radius: 16, y: 10)
    }
}

// MARK: - Details

struct CountryDetailView: View {
    let item: CountryRecommendation
    
    var body: some View {
        VStack(spacing: 16) {
            Text(item.emoji).font(.system(size: 72))
            Text(item.name).font(.largeTitle.bold())
            Text(item.subtitle).font(.title3).foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DiscoverScreen(path: .constant(NavigationPath()))
}
