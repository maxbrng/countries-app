//
//  DefaultSearchView.swift
//  Countries
//
//  Created by Max Breuning on 09.01.26.
//

import SwiftUI
import SwiftData

/// Content of the permanent base sheet on the map.
///
/// While nothing is typed the sheet shows the visit statistics and the country and date
/// filters; as soon as the search field carries text it shows the matching countries
/// instead. Selecting a country hands it to the ``MapScreenModel``, which presents the
/// country sheet on top of this one.
struct DefaultSearchView: View {

    // MARK: - Constants

    /// Spacing, insets and sizes of the sheet content.
    private enum Layout {

        /// Spacing between the search field and the close button.
        static let searchBarSpacing: CGFloat = 10

        /// Spacing between the magnifier, the field and the clear button.
        static let searchFieldSpacing: CGFloat = 8

        /// Inner padding of the glass search field.
        static let searchFieldPadding: CGFloat = 14

        /// Padding around the search bar inside the top bar.
        static let searchBarInset: CGFloat = 18

        /// Height of the search bar row, which also defines the collapsed sheet height.
        static let searchBarHeight: CGFloat = 48

        /// Upper bound of the top bar, so it cannot grow with the scroll view inside it.
        static let topBarMaxHeight: CGFloat = 90

        /// Vertical inset of the filter rows.
        static let listRowVerticalInset: CGFloat = 12

        /// Spacing inside the country filter card.
        static let filterSpacing: CGFloat = 12

        /// Spacing inside the date filter card.
        static let dateFilterSpacing: CGFloat = 8

        /// Spacing between a date picker and its caption.
        static let dateLabelSpacing: CGFloat = 5

        /// Corner radius of the filter cards.
        static let filterCornerRadius: CGFloat = 20

        /// Scale the close button transitions in and out from.
        static let closeButtonTransitionScale: CGFloat = 0.9
    }

    /// Animation durations of the search bar.
    private enum Timing {

        /// Focus changes, which move the search field and the close button together.
        static let focusChange: TimeInterval = 0.25

        /// Clearing the field with its own button.
        static let clearSearch: TimeInterval = 0.2
    }

    /// Defaults of the date filter.
    private enum DateFilter {

        /// The date filter starts this many years in the past.
        static let startYearOffset = -20
    }

    // MARK: - State

    @Bindable var model: MapScreenModel

    @State private var searchText = ""
    @State private var start: Date = Calendar.current.date(byAdding: .year,
                                                           value: DateFilter.startYearOffset,
                                                           to: Date()) ?? Date()
    @State private var end: Date = Date()

    /// The only focusable field of the sheet.
    private enum Field: Hashable {
        case search
    }

    @FocusState private var focusedField: Field?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Country.iso2) private var allCountries: [Country]

    // MARK: - Body

    var body: some View {

        NavigationStack {

            List {
                if isShowingResults {
                    resultsList

                } else {
                    Section {
                        StatView()
                        countryFilter
                        dateFilter
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(.vertical, Layout.listRowVerticalInset)
                }
            }
            // Hidden, not pushed down: an inset would change the scroll geometry.
            .opacity(model.hidesBaseSheetContent ? 0 : 1)
            .allowsHitTesting(!model.hidesBaseSheetContent)
            .animation(nil, value: model.hidesBaseSheetContent)
            .listStyle(.plain)
            .contentMargins(.top, 0)
            .safeAreaBar(edge: .top) {
                ScrollView { // needed else the safeareabar breaks the focusstate
                    searchBarWithCloseButton
                        .padding(Layout.searchBarInset)
                }
                .scrollDisabled(true)
                .frame(maxHeight: Layout.topBarMaxHeight)
            }
            // Collapsed on its own, meaning not pushed down by a stacked sheet, tells us
            // the user is done searching.
            .onChange(of: model.baseDetent) { _, detent in
                guard detent == .small, !model.isAnySecondarySheetPresented else { return }
                focusedField = nil
                searchText = ""
            }
            .onChange(of: model.presentedRoute) { _, _ in
                updateFocusForSheetState()
            }
        }
    }

    // MARK: - Search bar

    /// The search field plus the close button that appears while the field is focused.
    private var searchBarWithCloseButton: some View {

        HStack(spacing: Layout.searchBarSpacing) {

            searchBar
                .animation(.snappy(duration: Timing.focusChange), value: focusedField)

            if focusedField == .search {
                CloseButton {
                    withAnimation(.snappy(duration: Timing.focusChange)) {
                        focusedField = nil
                        searchText = ""
                    }
                }
                .transition(.scale(scale: Layout.closeButtonTransitionScale)
                    .combined(with: .opacity)
                    .combined(with: .move(edge: .trailing)))
            }
        }
        .frame(height: Layout.searchBarHeight)
        .animation(.snappy(duration: Timing.focusChange), value: focusedField)
    }

    /// The glass search field with its magnifier and clear button.
    private var searchBar: some View {

        HStack(spacing: Layout.searchFieldSpacing) {

            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)

            TextField("Search countries", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .search)
                .submitLabel(.search)
                .onChange(of: focusedField) { _, field in
                    model.isSearchFieldFocused = (field == .search)
                }

            if !searchText.isEmpty {
                Button {
                    withAnimation(.snappy(duration: Timing.clearSearch)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Layout.searchFieldPadding)
        .glassEffect()
    }

    // MARK: - Derived state

    /// All countries the current status filter allows.
    private var baseCountries: [Country] {

        var base = allCountries
        switch model.filter {
        case .all:
            break
        case .visited:
            base = base.filter { $0.status == .visited }
        case .wishlist:
            base = base.filter { $0.status == .wishlist }
        }
        return base
    }

    /// ``baseCountries`` narrowed by the search text and sorted by English name.
    private var filteredCountries: [Country] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = baseCountries
        let filtered: [Country]
        if trimmed.isEmpty {
            filtered = source
        } else {
            filtered = source.filter { country in
                // Simple search across name, ISO codes and, where present, alternative names.
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

    /// Whether the sheet shows results instead of the filters.
    private var isShowingResults: Bool {
        !searchText.isEmpty
    }

    /// Drops the focus while a sheet covers this one and restores it afterwards.
    private func updateFocusForSheetState() {

        if model.isAnySecondarySheetPresented {
            focusedField = nil
        } else if !searchText.isEmpty {
            focusedField = .search
        }
    }

    // MARK: - Sections when not searching

    /// Segmented control for the visited / wishlist filter.
    private var countryFilter: some View {

        VStack(alignment: .leading, spacing: Layout.filterSpacing) {

            Text("Country filter")
                .font(.callout)

            Picker("Filter", selection: $model.filter) {
                Text("All").tag(CountryStatusFilter.all)
                Text("Visited").tag(CountryStatusFilter.visited)
                Text("Wishlist").tag(CountryStatusFilter.wishlist)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Layout.filterCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    /// The two date pickers, kept in order so the range can never invert.
    private var dateFilter: some View {

        VStack(alignment: .leading, spacing: Layout.dateFilterSpacing) {

            Text("Timerange")
                .font(.callout)

            HStack {
                // TODO: add custom range slider with glasseffect later
                VStack(alignment: .leading, spacing: Layout.dateLabelSpacing) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("Von", selection: $start, in: ...end, displayedComponents: .date)
                        .labelsHidden()
                }
                .fixedSize()

                Spacer()

                VStack(alignment: .leading, spacing: Layout.dateLabelSpacing) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("Bis", selection: $end, in: start..., displayedComponents: .date)
                        .labelsHidden()
                }
                .fixedSize()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Layout.filterCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onChange(of: start) { _, newValue in
            if newValue > end { end = newValue }
        }
        .onChange(of: end) { _, newValue in
            if newValue < start { start = newValue }
        }
    }

    // MARK: - Results list (shown when searching)

    /// The search results, or an empty state when nothing matches.
    private var resultsList: some View {

        Section {
            if filteredCountries.isEmpty {
                ContentUnavailableView("No country found.",
                                       systemImage: "magnifyingglass",
                                       description: Text("Check the spelling or try a new search"))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredCountries, id: \.iso2) { country in
                    // A button, not a tap gesture: picking a result is an action, and only the
                    // button carries the accessibility trait that tells VoiceOver so.
                    Button {
                        model.selectedCountry = country
                    } label: {
                        CountryRow(country: country)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - CloseButton

/// A round glass button with an `xmark` glyph.
struct CloseButton: View {

    /// Sizes of the button and its glyph.
    private enum Layout {

        /// Point size of the `xmark` glyph.
        static let glyphFontSize: CGFloat = 26

        /// Width of the glyph's tap and clip shape.
        static let glyphWidth: CGFloat = 26

        /// Height of the glyph's tap and clip shape.
        static let glyphHeight: CGFloat = 34

        /// Outer size of the button, matching the search bar height.
        static let buttonSize: CGFloat = 48
    }

    /// Invoked when the button is tapped.
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Layout.glyphFontSize, weight: .regular))
                .contentShape(Circle())
                .clipShape(Circle())
                .frame(width: Layout.glyphWidth, height: Layout.glyphHeight)
        }
        .frame(width: Layout.buttonSize, height: Layout.buttonSize)
        .buttonStyle(.glass)
    }
}
