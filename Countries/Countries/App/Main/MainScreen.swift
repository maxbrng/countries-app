//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries", category: "MainScreen")

struct MainScreen: View {
    
    @Binding var path: NavigationPath
    @StateObject private var viewModel = MainScreenViewModel()
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Country.iso2) private var allCountries: [Country]
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    
    var body: some View {
        
        ScrollView {
            
            LazyVStack(spacing: 40) {
                
                NavigationLink("Globe") {
                    GlobeMapView()
                }
                
                NavigationLink(value: AppRoute.mapScreen) {
                    
                    StaticCountriesMapView(selectionEnabled: false, labelsEnabled: false, projectionMode: .plateCarree)
                        .disabled(true)
                        .padding(.horizontal)
                        .aspectRatio(1.8, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
                        .padding(.top)
                }
                
                statView
                
                countryCard
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Your Countries")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            let source = showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries
            viewModel.update(from: source)
        }
        .onChange(of: allCountries) { _, newValue in
            let source = showOnlyUNMembers ? newValue.filter { $0.isUNMember } : newValue
            viewModel.update(from: source)
        }
        .onChange(of: showOnlyUNMembers) { _, newValue in
            let source = newValue ? allCountries.filter { $0.isUNMember } : allCountries
            viewModel.update(from: source)
        }
    }
    
    // MARK: - Statistic
    
    var statView: some View {
        
        HStack(alignment: .center, spacing: 0) {
            statistic(currentValue: viewModel.countriesVisited,
                      maxValue: viewModel.totalCountries,
                      text: "countries",
                      graphVisualization: false)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: viewModel.countriesVisited,
                      maxValue: viewModel.totalCountries,
                      text: "of the world",
                      graphVisualization: true)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: viewModel.continentsVisited,
                      maxValue: viewModel.totalContinents,
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
                
                Gauge(value: progress) {
                    Text(verbatim: text)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .gaugeStyle(CircularStrokeGaugeStyle(lineWidth: 8))
                .frame(width: 60, height: 60)
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
    
    // MARK: - CountryCard
    
    var countryCard: some View {
        
        NavigationLink(value: AppRoute.fullCountryList) {
            
            VStack(alignment: .leading, spacing: 16) {
                
                Text(verbatim: "Countries & Territories")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(alignment: .top, spacing: 24) {
                    countryPreviewList(for: "Visited", countries: viewModel.visitedCountries)
                    
                    countryPreviewList(for: "On Wishlist", countries: viewModel.wishlistCountries)
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
                                    countries: [Country]) -> some View {
        
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
                
                ForEach(countries.prefix(3), id: \.iso2) { country in
                    
                    HStack(spacing: 8) {
                        
                        Image(country.iso2.lowercased())
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                            .frame(maxWidth: 15, maxHeight: 10)
                        
                        Text(country.nameEnglish)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .truncationMode(.tail)
                            .lineLimit(1)
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

