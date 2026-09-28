//
//  TripCountryPickerView.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftData
import SwiftUI

/// Multi-selection country picker, pushed from ``TripEditorView``.
///
/// Writes straight into the editor's draft, so the selection is discarded with the draft when
/// the editor is cancelled.
struct TripCountryPickerView: View {

    // MARK: - Properties

    /// ISO2 codes of the selected countries, owned by the editor's draft.
    @Binding var selectedCodes: Set<String>

    // MARK: - Body

    var body: some View {

        CountryMultiSelectList(selectedCodes: $selectedCodes,
                               searchPrompt: "Search countries")
            .navigationTitle("Countries")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TripCountryPickerView(selectedCodes: .constant(["DE", "FR"]))
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
