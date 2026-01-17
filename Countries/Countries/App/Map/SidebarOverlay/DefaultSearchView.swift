//
//  DefaultSearchView.swift
//  Countries
//
//  Created by Max Breuning on 09.01.26.
//

import SwiftUI
import SwiftData

/// Diese View wird im permanenten Sheet angezeigt,
/// wenn selectedCountry == nil und showAppearancePanel == false ist.
struct DefaultSearchView: View {
    
    @State var searchText = ""
    
    private enum Field: Hashable {
        case search
    }
    
    @FocusState private var focusedField: Field?
    
    @Query(sort: \Country.iso2) private var allCountries: [Country]
    
    @State private var sortAscending: Bool = true
    @State private var showOnlyUNMembers: Bool = false
    
    var body: some View {
        
        NavigationStack {
            
            ScrollView {
                
                VStack(alignment: .leading, spacing: 20) {
                    
                    if !isShowingResults {
                        filterSection
                        statisticsSection
                        tipsSection
                    } else {
                        resultsList
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            .safeAreaBar(edge: .top) {
                ScrollView { // needed else the safeareabar breaks the focusstate
                    searchbarWithCloseButton
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                        .zIndex(10)
                        .padding(18)
                        .frame(maxWidth: .infinity)
                }
                .scrollDisabled(true)
                .frame(maxHeight: 90)
            }
        }
    }
    
    // MARK: - Derived state
    
    var searchbarWithCloseButton: some View {
        
        HStack(spacing: 10) {
            
            searchbar
                .animation(.snappy(duration: 0.25), value: focusedField)
            
            if focusedField == .search {
                CloseButton {
                    withAnimation(.snappy(duration: 0.25)) {
                        focusedField = nil
                        searchText = ""
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.25), value: focusedField)
    }
    
    var searchbar: some View {
        
        HStack(spacing: 8) {
            
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            
            TextField("Search countries", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .search)
            
            if !searchText.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassEffect()
    }
    
    private var baseCountries: [Country] {
        showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries
    }
    
    private var filteredCountries: [Country] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = baseCountries
        let filtered: [Country]
        if trimmed.isEmpty {
            filtered = source
        } else {
            filtered = source.filter { country in
                // Einfache Suche über Name, ISO Codes und ggf. alternative Namen
                let haystack = [
                    country.nameEnglish,
                    country.iso2,
                    country.iso3
                ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                
                return haystack.contains(trimmed.lowercased())
            }
        }
        
        if sortAscending {
            return filtered.sorted { ($0.nameEnglish) < ($1.nameEnglish) }
        } else {
            return filtered.sorted { ($0.nameEnglish) > ($1.nameEnglish) }
        }
    }
    
    private var isShowingResults: Bool {
        !searchText.isEmpty
    }
    
    // MARK: - Sections when not searching
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map filters")
                .font(.headline)
            Text("Hier kannst du später die Karte filtern (Kontinente, Kategorien, besuchte Länder, Wunschliste, etc.).")
                .foregroundStyle(.secondary)
            Toggle(isOn: $showOnlyUNMembers) {
                Label("Only UN members", systemImage: "globe")
            }
            .toggleStyle(.switch)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var statisticsSection: some View {
        
        StatView(viewModel: MainScreenViewModel())
        
    }
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tip")
                .font(.headline)
            Text("Tippe in die Suchleiste oben, um nach Ländernamen, ISO2 oder ISO3 zu suchen. Die Ergebnisliste erscheint dann hier.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Results list (shown when searching)
    
    private var resultsList: some View {
        Group {
            if filteredCountries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No results")
                        .font(.headline)
                    Text("Keine Länder gefunden. Probiere einen anderen Suchbegriff.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Eine einfache Liste der Länder, ähnlich zur CountriesList (ohne Gruppen)
                VStack(spacing: 0) {
                    ForEach(filteredCountries, id: \.iso2) { country in
                        NavigationLink(destination: CountryDetailsView(country: country)) {
                            CountryRow(country: country)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(action: { sortAscending.toggle() }) {
                    Label(sortAscending ? "Sort Z→A" : "Sort A→Z", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func statPill(title: String, value: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let value { Text("\(value)").font(.headline) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(Color(.tertiarySystemFill))
        )
    }
    
    private func statPill(title: String, value: Int?, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(Color(.tertiarySystemFill))
        )
    }
}


struct CloseButton: View {
    
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 26, weight: .regular))
                .contentShape(Circle())
                .clipShape(Circle())
                .frame(width: 26, height: 34)
        }
        .buttonStyle(.glass)
    }
}

#Preview {
    DefaultSearchView()
}
