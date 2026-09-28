//
//  CountriesList.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import SwiftData

/// Full country list, used twice: as the root of the search tab (with a bound search field)
/// and as a pushed screen from the main screen (without one).
///
/// Grouped by continent while the search field is empty and flat while it is not.
struct CountriesList: View {

    // MARK: - Layout

    /// Sizes and radii of the segmented-picker header.
    private enum Layout {
        static let headerCornerRadius: CGFloat = 30
        static let headerBorderWidth: CGFloat = 1
        static let headerHeight: CGFloat = 40
        /// Extra inset of the picker beyond its default padding.
        static let headerExtraHorizontalPadding: CGFloat = 4
        /// Top inset that keeps the first section header clear of the floating header.
        static let firstSectionTopPadding: CGFloat = 20
        /// Height of the spacer header used by the ungrouped list, matching
        /// ``firstSectionTopPadding`` so both layouts start at the same offset.
        static let ungroupedHeaderHeight: CGFloat = 20
    }

    // MARK: - Properties

    /// Supplied by the call site. The search tab owns a field and binds it here;
    /// the pushed screen passes a constant and shows no field at all, because a
    /// navigation-bar search field there swallows the first Back tap.
    @Binding var searchText: String

    @StateObject private var viewModel = CountriesListViewModel()
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query(sort: \Country.iso2) private var allCountries: [Country]

    // MARK: - Init

    /// Creates the list.
    ///
    /// - Parameter searchText: Binding to the call site's search field. Defaults to
    ///   `.constant("")`, which is what the pushed screen passes since it has no field.
    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    // MARK: - Body

    var body: some View {

        let base = showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries
        let filtered = viewModel.filteredCountries(from: base, searchText: searchText)

        List {
            if filtered.isEmpty {
                // Without a search term an empty result is the filter's doing, not a typo,
                // so it gets its own message instead of asking about the spelling.
                emptyState(isSearching: !searchText.isEmpty,
                           storeIsEmpty: allCountries.isEmpty)
            } else if searchText.isEmpty {
                // Grouped only here: the search branch discards the grouping.
                groupedList(groups: viewModel.groups(from: filtered))
            } else {
                ungroupedList(countries: filtered)
            }
        }
        .toolbar { sortToolbar }
        .navigationTitle("All countries")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { listHeaderWithSegmentedPicker }
    }

    // MARK: - Empty state

    /// Shown whenever the list has nothing to display.
    ///
    /// The three cases are told apart on purpose: only a search makes "check the spelling"
    /// useful, and offering to turn the filter off is wrong when there is nothing to show
    /// in the first place.
    ///
    /// - Parameters:
    ///   - isSearching: Whether a search term is entered.
    ///   - storeIsEmpty: Whether the store holds no countries at all, which means the seed
    ///     did not run rather than that a filter is hiding them.
    @ViewBuilder
    private func emptyState(isSearching: Bool, storeIsEmpty: Bool) -> some View {

        if isSearching {
            ContentUnavailableView("No country found.",
                                   systemImage: "magnifyingglass",
                                   description: Text("Check the spelling or try a new search"))
        } else if storeIsEmpty {
            ContentUnavailableView {
                Label("No countries", systemImage: "globe")
            } description: {
                Text("The country data could not be loaded. Restarting the app rebuilds it.")
            }
        } else {
            ContentUnavailableView {
                Label("No countries", systemImage: "globe")
            } description: {
                Text("The UN filter is hiding every country.")
            } actions: {
                Button("Show all countries") { showOnlyUNMembers = false }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {

        ToolbarItem(placement: .topBarTrailing) {

            Menu {
                Button(action: { viewModel.sortAscending.toggle() }) {
                    Label(viewModel.sortAscending ? "Sort Z→A" : "Sort A→Z",
                          systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
        }
    }

    // MARK: - Lists

    /// Continent-grouped sections, shown while no search term is entered.
    ///
    /// - Parameter groups: Already sorted groups from ``CountriesListViewModel/groups(from:)``.
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
                    .padding(.top, index == 0 ? Layout.firstSectionTopPadding : 0)
            }
        }
    }

    /// Flat section of search results.
    ///
    /// - Parameter countries: The matching countries in their current sort order.
    @ViewBuilder
    private func ungroupedList(countries: [Country]) -> some View {

        Section {

            ForEach(countries, id: \.iso2) { country in
                NavigationLink(destination: CountryDetailsView(country: country)) {
                    CountryRow(country: country)
                }
            }
        } header: {
            Color.clear.frame(height: Layout.ungroupedHeaderHeight)
        }
    }

    // MARK: - Header

    /// Status filter pinned above the list on a translucent, rounded backdrop.
    private var listHeaderWithSegmentedPicker: some View {

        ZStack {

            RoundedRectangle(cornerRadius: Layout.headerCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.headerCornerRadius, style: .continuous)
                        .stroke(Color(uiColor: .tertiarySystemFill),
                                lineWidth: Layout.headerBorderWidth)
                        // Masks away the top edge of the stroke so the backdrop reads as
                        // attached to the navigation bar.
                        .mask(Rectangle().padding(.top, 1))
                )
                .ignoresSafeArea(edges: .top)

            Picker("Filter", selection: $viewModel.filter) {
                ForEach(CountryStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .padding(.horizontal, Layout.headerExtraHorizontalPadding)
        }
        .frame(height: Layout.headerHeight)
    }
}
