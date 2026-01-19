//
//  CountriesList.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import SwiftData

struct CountriesList: View {
    
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CountriesListViewModel()
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query(sort: \Country.iso2) private var allCountries: [Country]
    
    var body: some View {
        
        let base = showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries
        let filtered = viewModel.filteredCountries(from: base)
        let groups = viewModel.groups(from: filtered)
        
        List {
            if viewModel.search.isEmpty {
                groupedList(groups: groups)
            } else {
                
                if filtered.isEmpty {
                    ContentUnavailableView("No country found.", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search"))
                } else {
                    ungroupedList(countries: filtered)
                }
            }
        }
        .searchable(text: $viewModel.search)
        .toolbar { sortToolbar }
        .navigationTitle("All countries")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { listHeaderWithSegmentedPicker }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        
        ToolbarItem(placement: .topBarTrailing) {
            
            Menu {
                Button(action: { viewModel.sortAscending.toggle() }) {
                    Label(viewModel.sortAscending ? "Sort Z→A" : "Sort A→Z", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private func groupedList(groups: [CountriesListViewModel.CountryGroup]) -> some View {
        
        ForEach(Array(groups.enumerated()), id: \.element.continentCode) { index, group in
            
            Section {
                
                ForEach(group.countries, id: \.iso2) { country in
                    NavigationLink(destination: CountryDetailsView(country: country)) {
                        CountryRow(country: country)
                    }
                }
            } header: {
                Text(group.title)
                    .padding(.top, index == 0 ? 20 : 0)
            }
        }
    }


    @ViewBuilder
    private func ungroupedList(countries: [Country]) -> some View {
        
        Section {
            
            ForEach(countries, id: \.iso2) { country in
                NavigationLink(destination: CountryDetailsView(country: country)) {
                    CountryRow(country: country)
                }
            }
        } header: {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Header

    private var listHeaderWithSegmentedPicker: some View {
        
        ZStack {
            
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                        .mask(Rectangle().padding(.top, 1))
                )
                .ignoresSafeArea(edges: .top)

            Picker("Filter", selection: $viewModel.filter) {
                Text("All").tag(CountryStatusFilter.all)
                Text("Visited").tag(CountryStatusFilter.visited)
                Text("Wishlist").tag(CountryStatusFilter.wishlist)
            }
            .pickerStyle(.segmented)
            .padding()
            .padding(.horizontal, 4)
        }
        .frame(height: 40)
    }
}

