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
    
    var body: some View {
        
        ScrollView {
            
            LazyVStack(spacing: 40) {
                
                NavigationLink(value: AppRoute.mapScreen) {
                    
                    FlatMapView(selectionEnabled: false,
                                labelsEnabled: false,
                                renderMode: .stretch,
                                projectionMode: .plateCarree,
                                selectedCountry: .constant(nil),
                                filter: .constant(.all))
                        .disabled(true)
                        .padding(.horizontal)
                        .aspectRatio(1.8, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
                        .padding(.top)
                }
                
                StatView()
                
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

