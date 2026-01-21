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
    
    @StateObject private var service = PhotoService()
    @State private var sortAscending: Bool = true
    
    private var displayedCountries: [Country] {
        allCountries.sorted { a, b in
            if sortAscending {
                return a.iso2 < b.iso2
            } else {
                return a.iso2 > b.iso2
            }
        }
    }
    
    var body: some View {
        
        GeometryReader { geo in
            let cardHeight = geo.size.height - 40
            let cardWidth = geo.size.width - 40
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: 0) {
                    
                    ForEach(displayedCountries) { country in
                        
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
                    sortAscending.toggle()
                } label: {
                    Label(sortAscending ? "A→Z" : "Z→A", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                }
                .accessibilityLabel(sortAscending ? "Sort descending" : "Sort ascending")
                .accessibilityHint("Toggle country sort order")
            }
        }
        .navigationDestination(for: Country.self) { country in
            CountryDetailsView(country: country)
        }
        .task(id: allCountries.count) {
            // 1) Erstmal “above the fold” + bisschen Buffer:
            let firstBatch = Array(displayedCountries.prefix(30))
            service.preload(countries: firstBatch)
            
            // 2) Optional: “gefühlt alles” – in kleinen Wellen nachladen
            // (Wenn du wirklich ALLES sofort willst: wiki.preloadAll(countries: allCountries))
            var index = 30
            while index < displayedCountries.count {
                let next = Array(displayedCountries[index..<min(index + 20, displayedCountries.count)])
                service.preload(countries: next)
                index += 20
                
                // kleine Pause, damit UI nicht leidet (und Server nicht komplett stresst)
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }
        .onDisappear {
            // Optional: wenn du willst, dass beim Verlassen abgebrochen wird
            service.cancelAll()
        }
    }
}

