//
//  OnboardingHomeView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI

/// The first launch's last question: where the user lives.
///
/// Optional like every other step. It exists because the home country is the one a traveller
/// never thinks to mark, and it is the reference point the map is read from.
struct OnboardingHomeView: View {

    // MARK: - Layout

    /// Spacings of the heading above the list.
    private enum Layout {
        static let headerSpacing: CGFloat = 8
        static let headerBottomPadding: CGFloat = 8
    }

    // MARK: - Properties

    /// ISO2 code of the picked country, owned by ``OnboardingFlowView``.
    @Binding var selectedCode: String?

    // MARK: - Body

    var body: some View {

        VStack(alignment: .leading, spacing: Layout.headerSpacing) {

            Text("Where do you live?")
                .font(.largeTitle.bold())

            Text("Your home country counts as visited. You can change it later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)

            selectionSummary

            CountryMultiSelectList(selectedCodes: singleSelectionBinding(for: $selectedCode),
                                   searchPrompt: "Search countries")
                .listStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    /// Names the picked country, or says that none is picked.
    @ViewBuilder
    private var selectionSummary: some View {

        Group {
            if selectedCode == nil {
                Text("Nothing selected yet")
            } else {
                Text("One country selected")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.bottom, Layout.headerBottomPadding)
    }
}

#Preview {
    OnboardingHomeView(selectedCode: .constant("DE"))
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
