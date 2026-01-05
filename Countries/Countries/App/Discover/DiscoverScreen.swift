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
    @StateObject private var viewModel = DiscoverViewModel()
    
    var body: some View {
        
        GeometryReader { geo in
            let cardHeight = geo.size.height - 40
            
            ScrollView(.vertical) {
                
                LazyVStack(spacing: 0) {

                    ForEach(viewModel.items) { item in
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
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: CountryRecommendation.self) { item in
            CountryDetailView(item: item)
        }
    }
}

#Preview {
    DiscoverScreen(path: .constant(NavigationPath()))
}

