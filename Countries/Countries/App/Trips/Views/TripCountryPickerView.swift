//
//  TripCountryPickerView.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import SwiftData

/// Multi-selection country picker, pushed from ``TripEditorView``.
///
/// Writes straight into the editor's draft, so the selection is discarded with the draft when
/// the editor is cancelled.
struct TripCountryPickerView: View {

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

    /// ISO2 codes of the selected countries, owned by the editor's draft.
    @Binding var selectedCodes: Set<String>

    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query(sort: \Country.nameEnglish) private var allCountries: [Country]

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
        .searchable(text: $searchText, prompt: "Search countries")
        .overlay {
            if filteredCountries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Countries")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content

    /// The countries offered, narrowed by the UN filter and the search field.
    private var filteredCountries: [Country] {

        let base = showOnlyUNMembers ? allCountries.filter(\.isUNMember) : allCountries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return base }

        return base.filter {
            $0.nameEnglish.localizedCaseInsensitiveContains(query)
                || $0.iso2.localizedCaseInsensitiveContains(query)
        }
    }

    /// One row: flag, name and a checkmark while the country is selected.
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

            Text(country.nameEnglish)

            Spacer()

            if selectedCodes.contains(country.iso2) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selectedCodes.contains(country.iso2) ? [.isSelected] : [])
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
        TripCountryPickerView(selectedCodes: .constant(["DE", "FR"]))
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
