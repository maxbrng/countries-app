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
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Country.iso2) private var allCountries: [Country]
    
    @Binding var selectedCountry: Country?
    @Binding var filter: CountryStatusFilter
    
    var body: some View {
        
        NavigationStack {
            
            Group {
                
                if !isShowingResults {
                    
                    ScrollView {
                        VStack(spacing: 30) {
                            filterSection
                            StatView()
                            Spacer()
                        }
                        .padding()
                    }
                    
                } else {
                    
                    List {
                        resultsList
                    }
                    .contentMargins(.top, 0)
                }
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
        
        var base = allCountries
        switch filter {
        case .all:
            break
        case .visited:
            base = base.filter { $0.status == .visited }
        case .wishlist:
            base = base.filter { $0.status == .wishlist }
        }
        return base
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
        
        
        return filtered.sorted { ($0.nameEnglish) < ($1.nameEnglish) }
    }
    
    private var isShowingResults: Bool {
        !searchText.isEmpty
    }
    
    // MARK: - Sections when not searching
    
    private var filterSection: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            
            Text("Map filters")
                .font(.headline)
            
            Picker("Filter", selection: $filter) {
                Text("All").tag(CountryStatusFilter.all)
                Text("Visited").tag(CountryStatusFilter.visited)
                Text("Wishlist").tag(CountryStatusFilter.wishlist)
            }
            .pickerStyle(.segmented)
            
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
        
        Section {
            if filteredCountries.isEmpty {
                ContentUnavailableView("No country found.", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search"))
            } else {
                ForEach(filteredCountries, id: \.iso2) { country in
                    CountryRow(country: country)
                        .onTapGesture {
                            selectedCountry = country
                        }
                }
            }
        }
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
