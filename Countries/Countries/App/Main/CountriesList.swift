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
    @State private var search: String = ""
    @State private var filter: CountryStatusFilter = .all
    @State private var sortAscending: Bool = true
    
    private struct ContinentGroup: Identifiable {
        let id: String
        let title: String
        let countries: [Country]
    }
    
    private func fullContinentName(from raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Other" }
        switch raw.uppercased() {
        case "AF": return "Africa"
        case "AN": return "Antarctica"
        case "AS": return "Asia"
        case "EU": return "Europe"
        case "NA": return "North America"
        case "SA": return "South America"
        case "OC": return "Oceania"
        default: return raw
        }
    }
    
    private func continentGroups() -> [ContinentGroup] {
        let groups = Dictionary(grouping: items()) { (country: Country) in
            fullContinentName(from: country.continent)
        }
        
        let sortedKeys = groups.keys.sorted {
            let cmp = $0.localizedCaseInsensitiveCompare($1)
            return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        
        return sortedKeys.map { key in
            let countries = groups[key] ?? []
            let sorted = countries.sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return sortAscending ? (order == .orderedAscending) : (order == .orderedDescending)
            }
            return ContinentGroup(id: key, title: key, countries: sorted)
        }
    }
    
    var body: some View {
        
        List {
            if search.isEmpty {
                let groups = continentGroups()
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    Section {
                        ForEach(group.countries, id: \.iso2) { country in
                            countryRow(country)
                        }
                    } header: {
                        Text(group.title)
                            .padding(.top, index == 0 ? 20 : 0)
                    }
                }
            } else {
                Section {
                    ForEach(items(), id: \.iso2) { country in
                        countryRow(country)
                    }
                } header: {
                    Color.clear
                        .frame(height: 20)
                }
            }
        }
        .searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { sortAscending.toggle() }) { Label(sortAscending ? "Sort Z→A" : "Sort A→Z", systemImage: "arrow.up.arrow.down") }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down.circle") }
            }
        }
        .navigationTitle("All countries")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                            .mask(
                                Rectangle()
                                    .padding(.top, 1) // hide the top 1pt of the stroke
                            )
                        )
                    .ignoresSafeArea(edges: .top)
                
                Picker("Filter", selection: $filter) {
                    Text("All").tag(CountryStatusFilter.all as CountryStatusFilter)
                    Text("Visited").tag(CountryStatusFilter.visited as CountryStatusFilter)
                    Text("Wishlist").tag(CountryStatusFilter.wishlist as CountryStatusFilter)
                }
                .pickerStyle(.segmented)
                .padding()
                .padding(.horizontal, 4)
            }
            .frame(height: 40)
        }
    }
    
    @ViewBuilder
    private func countryRow(_ country: Country) -> some View {
        HStack(spacing: 16) {
            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading) {
                Text(country.name)
                Text(country.iso2).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badge(for: country.status)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { try? CountryRepository(context: modelContext).toggleVisited(for: country.iso2) } label: { Label("Visited", systemImage: "checkmark.circle") }.tint(.green)
            Button { try? CountryRepository(context: modelContext).toggleWishlist(for: country.iso2) } label: { Label("Wishlist", systemImage: "star") }.tint(.blue)
        }
    }
    
    @ViewBuilder
    func badge(for status: CountryStatus) -> some View {
        switch status {
        case .none: EmptyView()
        case .visited: Text("Visited")
                .padding(4)
                .padding(.horizontal, 6)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
        case .wishlist: Text("Wishlist")
                .padding(4)
                .padding(.horizontal, 6)
                .background(.blue.opacity(0.2))
                .clipShape(Capsule())
        }
    }
    
    func items() -> [Country] {
        let repo = CountryRepository(context: modelContext)
        let base = (try? repo.fetchAll(search: nil, filter: filter, sortAscending: sortAscending)) ?? []
        guard !search.isEmpty else { return base }
        let filtered = base.filter { c in
            c.name.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            c.iso2.range(of: search, options: [.caseInsensitive]) != nil
        }
        return filtered.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return sortAscending ? (order == .orderedAscending) : (order == .orderedDescending)
        }
    }
}

private struct RoundedBottomCorners: Shape {
    var radius: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
