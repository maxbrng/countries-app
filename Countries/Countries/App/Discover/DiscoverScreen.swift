//
//  DiscoverScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import SwiftData

struct DiscoverScreen: View {
    
    @Binding var path: NavigationPath
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Country.iso2) private var allCountries: [Country]
    @Query(sort: \Trip.startDate, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \UserPreferences.updatedAt, order: .reverse) private var allPreferences: [UserPreferences]
    
    @AppStorage("selectedMockUser") private var selectedMockUser: Int = 0
    
    @StateObject private var service = PhotoService()
    @State var algoSettingsSheet = false
    
    private var activePreferences: UserPreferences? {
        allPreferences.first(where: { $0.profileKey == selectedMockUser })
    }
    
    private var recommendations: [RecommendationService.Recommendation] {
        guard let prefs = activePreferences else { return [] }
        return RecommendationService.recommendTopCountries(
            allCountries: allCountries,
            trips: allTrips,
            preferences: prefs,
            topN: 25
        )
    }
    
    private var recommendedCountries: [Country] {
        recommendations.map { $0.country }
    }
    
    var body: some View {
        
        GeometryReader { geo in
            let cardHeight = geo.size.height - 40
            let cardWidth = geo.size.width - 40
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: 0) {
                    
                    ForEach(recommendedCountries) { country in
                        
                        NavigationLink(value: country) {
                            
                            CountryCardView(country: country,
                                            height: cardHeight,
                                            width: cardWidth,
                                            service: service)
                            
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                            .frame(width: cardWidth, height: cardHeight)
                            .frame(maxWidth: cardWidth, maxHeight: cardHeight)
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
            .edgesIgnoringSafeArea(.all)
        }
        .navigationTitle("Recommendations")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    algoSettingsSheet.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $algoSettingsSheet) {
            AlgoSettingsSheetView()
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: Country.self) { country in
            CountryDetailsView(country: country)
        }
        .task(id: recommendedCountries.count) {
            let firstBatch = Array(recommendedCountries.prefix(30))
            service.preload(countries: firstBatch)
            
            var index = 30
            while index < recommendedCountries.count {
                let next = Array(recommendedCountries[index..<min(index + 20, recommendedCountries.count)])
                service.preload(countries: next)
                index += 20
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        .onDisappear {
            // Optional: wenn du willst, dass beim Verlassen abgebrochen wird
            service.cancelAll()
        }
    }
}
