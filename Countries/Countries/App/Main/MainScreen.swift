//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit

struct MainScreen: View {
    
    @Binding var path: NavigationPath
    
    @State private var countriesVisited: Double = 16
    @State private var continentsVisited: Double = 1
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    
    var body: some View {
        
        ScrollView {
            LazyVStack(spacing: 40) {
                NavigationLink(value: AppRoute.mapScreen) {
                    Map()
                        .disabled(true)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
                        .padding(.top)
                }
                
                statView()
                
                countryCard()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Your Countries")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
    
    // MARK: - Statistic
    
    @ViewBuilder
    func statView() -> some View {
        
        HStack(alignment: .center, spacing: 0) {
            statistic(currentValue: countriesVisited,
                      maxValue: 195,
                      text: "countries",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: countriesVisited,
                      maxValue: 195,
                      text: "of the world",
                      graphVisualization: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: continentsVisited,
                      maxValue: 7,
                      text: "continents",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        
    }
    
    @ViewBuilder
    func statistic(currentValue: Double,
                   maxValue: Double,
                   text: String,
                   graphVisualization: Bool) -> some View {
        
        VStack {
            
            if graphVisualization {
                let progress = max(0, min(1, currentValue / maxValue))
                let countryPercentage = progress * 100.0
                let text = String(format: "%.0f%%", countryPercentage)
                
                circularProgressView(progress: progress, text: text)
                    .padding(.bottom, 4)
                
            } else {
                
                Text("\(Int(currentValue))/\(Int(maxValue))")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    func circularProgressView(progress: Double,
                              text: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
            
            Text(verbatim: text)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .frame(width: 60, height: 60)
    }
    
    // MARK: - CountryCard
    
    @ViewBuilder
    func countryCard() -> some View {
        
        //TODO: Replace Mockvalues and flags
        let visited: [(flag: String, name: String)] = [
            ("🇫🇷", "France"),
            ("🇦🇹", "Austria"),
            ("🇨🇿", "Czech Republic"),
            ("🇨🇿", "Czech Republic"),
            ("🇨🇿", "Czech Republic"),
            ("🇨🇿", "Czech Republic"),
            ("🇨🇿", "Czech Republic")
        ]
        let wishlist: [(flag: String, name: String)] = [
            ("🇩🇪", "Germany")
        ]

        NavigationLink(value: AppRoute.fullCountryList) {
            
            VStack(alignment: .leading, spacing: 16) {
                
                Text(verbatim: "Countries & Territories")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(alignment: .top, spacing: 24) {
                    countryPreviewList(for: "Visited", countries: visited)
                    
                    countryPreviewList(for: "On Wishlist", countries: wishlist)
                }
                
                Divider()
                
                cardDetailLink()
            }
        }
        .tint(.primary)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 36))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func countryPreviewList(for text: String,
                                    countries: [(flag: String, name: String)]) -> some View {
        
        let remainingVisited = max(0, countries.count - 3)
        
        VStack(alignment: .leading, spacing: 8) {
            
            HStack(spacing: 6) {
                
                Text(verbatim: "\(countries.count)")
                    .font(.headline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(verbatim: text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                
                ForEach(countries.prefix(3), id: \.name) { item in
                    
                    HStack(spacing: 8) {
                        Text(item.flag)
                        Text(item.name)
                            .foregroundStyle(.primary)
                    }
                    .font(.footnote)
                }
                if remainingVisited > 0 {
                    Text("+\(remainingVisited) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func cardDetailLink() -> some View {
        
        HStack {
            Text("See Full List")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    MainScreen(path: .constant(NavigationPath()))
}

