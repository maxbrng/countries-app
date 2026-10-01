//
//  HomeCountryPickerView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "Settings")

/// Changes the home country after the first launch, pushed from ``SettingsScreen``.
///
/// Writes as the user taps rather than on a Done button: there is one answer, and a picker
/// that needs confirming for a single tap is a form.
struct HomeCountryPickerView: View {

    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext

    /// Mirrors the stored code so the list can bind to it.
    @State private var selectedCode: String?

    // MARK: - Body

    var body: some View {

        CountryMultiSelectList(selectedCodes: singleSelectionBinding(for: $selectedCode),
                               searchPrompt: "Search countries")
            .navigationTitle("Home country")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { selectedCode = HomeCountry.iso2 }
            .onChange(of: selectedCode) { _, newValue in
                store(newValue)
            }
    }

    // MARK: - Actions

    /// Writes the new home country.
    ///
    /// - Parameter code: The picked code, or `nil` when the user cleared it.
    private func store(_ code: String?) {

        do {
            try HomeCountry.set(code, in: modelContext)
        } catch {
            logger.error(
                "Could not store the home country: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

#Preview {
    NavigationStack {
        HomeCountryPickerView()
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
