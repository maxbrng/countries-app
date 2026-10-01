//
//  CountryMultiSelectList.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI

/// A searchable list of countries with a multi-selection.
///
/// Shared by the trip editor and the first launch, which need the same list for different
/// reasons. The selection is a set of ISO2 codes rather than of ``Country`` objects, so a
/// caller can hold it in a draft or in view state without keeping model objects alive.
///
/// The selection is `List`'s own, with the edit mode held active. That is not a detail: the
/// system selection lets you press and drag down the rows to take a run of them in one
/// gesture, which is what makes marking twenty countries quick. The hand-built row of
/// checkmarks this replaced could only ever be tapped one at a time, and looked like a list
/// of buttons rather than a selection.
///
/// - Note: Brings no navigation title of its own; the screen around it decides what this list
///   is called, because "Countries" and "Where have you been?" are the same list.
struct CountryMultiSelectList: View {

    // MARK: - Layout

    /// Sizes and radii of the flag shown in a row.
    private enum Layout {
        static let contentSpacing: CGFloat = 16
        static let flagCornerRadius: CGFloat = 4
        static let flagBorderWidth: CGFloat = 1
        static let flagMaxWidth: CGFloat = 32
        static let flagMaxHeight: CGFloat = 24
    }

    // MARK: - Properties

    /// ISO2 codes of the selected countries, owned by the caller.
    @Binding var selectedCodes: Set<String>


    /// Placeholder of the search field.
    let searchPrompt: LocalizedStringKey

    /// Whether a continent header may take or drop all of its countries at once.
    ///
    /// Off for a question with exactly one answer - see ``singleSelectionBinding(for:)``.
    /// "Select all" on a list of possible home countries asks you to live everywhere.
    let allowsBulkSelection: Bool

    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query private var allCountries: [Country]

    /// Text of the search field.
    @State private var searchText = ""

    // MARK: - Init

    /// - Parameters:
    ///   - selectedCodes: ISO2 codes of the selected countries, owned by the caller.
    ///   - searchPrompt: Placeholder of the search field.
    ///   - allowsBulkSelection: Whether a continent header may take all of its countries at
    ///     once. Defaults to `true`; pass `false` for a question with one answer.
    init(selectedCodes: Binding<Set<String>>,
         searchPrompt: LocalizedStringKey,
         allowsBulkSelection: Bool = true) {

        self._selectedCodes = selectedCodes
        self.searchPrompt = searchPrompt
        self.allowsBulkSelection = allowsBulkSelection
    }

    // MARK: - Body

    var body: some View {

        List(selection: $selectedCodes) {
            ForEach(continentGroups, id: \.code) { group in
                Section {
                    ForEach(group.countries, id: \.iso2) { country in
                        row(for: country)
                    }
                } header: {
                    header(for: group)
                }
            }
        }
        // Held active so the selection circles are there without the user having to find an
        // Edit button first. The list exists to select from; there is no other mode for it.
        .environment(\.editMode, .constant(.active))
        .searchable(text: $searchText, prompt: searchPrompt)
        .overlay {
            if continentGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Grouping

    /// One continent and the countries on it that survived the filters.
    private struct ContinentGroup {

        /// Two-letter continent code, or ``ContinentName/unknownCode``.
        let code: String

        /// The continent's name in the app's language.
        let name: String

        /// The countries, sorted by their displayed name.
        let countries: [Country]

        /// ISO2 codes of every country in the group.
        var codes: Set<String> { Set(countries.map(\.iso2)) }
    }

    /// The countries offered, narrowed by the UN filter and the search field, by continent.
    ///
    /// Grouping is what makes a long list workable: twenty countries in Europe are one run of
    /// rows to drag across, and the header can take all of them at once.
    ///
    /// - Note: Sorted here rather than in the query, because the query can only sort by a
    ///   stored property and the displayed name is resolved per language.
    private var continentGroups: [ContinentGroup] {

        let base = showOnlyUNMembers ? allCountries.filter(\.isUNMember) : allCountries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? base : base.filter { $0.matches(searchQuery: query) }

        // ``ContinentName`` rather than the stored code: the list would otherwise read "AF"
        // and "EU", which is what the data holds but not what a continent is called.
        let grouped = Dictionary(grouping: matching) { country in
            country.continent?.trimmedNonEmpty ?? ContinentName.unknownCode
        }

        return grouped
            .map { code, countries in
                ContinentGroup(code: code,
                               name: ContinentName.name(for: code),
                               countries: countries.sortedByDisplayName())
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Content

    /// A continent's name, how many of it are picked, and a control that takes or drops them all.
    ///
    /// - Parameter group: The continent to describe.
    private func header(for group: ContinentGroup) -> some View {

        let codes = group.codes
        let selectedHere = codes.intersection(selectedCodes)
        let allSelected = selectedHere.count == codes.count

        return HStack {

            Text(group.name)

            Spacer()

            if allowsBulkSelection, !selectedHere.isEmpty {
                Text(verbatim: "\(selectedHere.count)/\(codes.count)")
                    .foregroundStyle(.secondary)
            }

            if allowsBulkSelection {
                bulkButton(allSelected: allSelected, codes: codes)
            }
        }
    }

    /// Takes or drops a whole continent.
    ///
    /// - Parameters:
    ///   - allSelected: Whether every country of the continent is already picked.
    ///   - codes: ISO2 codes of that continent.
    private func bulkButton(allSelected: Bool, codes: Set<String>) -> some View {

        Button(allSelected ? "Deselect all" : "Select all") {

            if allSelected {
                selectedCodes.subtract(codes)
                return
            }

            selectedCodes.formUnion(codes)
        }
        .font(.caption.weight(.semibold))
        .textCase(nil)
        .buttonStyle(.borderless)
    }

    /// One row: flag and name. The selection control is the list's own.
    ///
    /// - Parameter country: The country the row stands for.
    private func row(for country: Country) -> some View {

        HStack(spacing: Layout.contentSpacing) {

            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Layout.flagCornerRadius,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: Layout.flagBorderWidth)
                )
                .frame(maxWidth: Layout.flagMaxWidth, maxHeight: Layout.flagMaxHeight)

            Text(country.displayName)
        }
        .tag(country.iso2)
    }
}

#Preview {
    NavigationStack {
        CountryMultiSelectList(selectedCodes: .constant(["DE", "FR"]),
                               searchPrompt: "Search countries")
            .navigationTitle("Countries")
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
