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

    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query private var allCountries: [Country]

    /// Text of the search field.
    @State private var searchText = ""

    // MARK: - Body

    var body: some View {

        List {
            ForEach(filteredCountries, id: \.iso2) { country in
                Button {
                    toggle(country)
                } label: {
                    row(for: country)
                }
                .tint(.primary)
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .overlay {
            if filteredCountries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Content

    /// The countries offered, narrowed by the UN filter and the search field.
    ///
    /// - Note: Sorted here rather than in the query, because the query can only sort by a
    ///   stored property and the displayed name is resolved per language.
    private var filteredCountries: [Country] {

        let base = showOnlyUNMembers ? allCountries.filter(\.isUNMember) : allCountries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return base.sortedByDisplayName() }

        return base.filter { $0.matches(searchQuery: query) }.sortedByDisplayName()
    }

    /// One row: flag, name and a checkmark while the country is selected.
    ///
    /// - Parameter country: The country the row stands for.
    private func row(for country: Country) -> some View {

        let isSelected = selectedCodes.contains(country.iso2)

        return HStack(spacing: Layout.contentSpacing) {

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

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Actions

    /// Adds `country` to the selection, or removes it when it is already in.
    ///
    /// - Parameter country: The tapped country.
    private func toggle(_ country: Country) {

        if selectedCodes.contains(country.iso2) {
            selectedCodes.remove(country.iso2)
            return
        }
        selectedCodes.insert(country.iso2)
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
