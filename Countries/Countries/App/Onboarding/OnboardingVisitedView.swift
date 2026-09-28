//
//  OnboardingVisitedView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI

/// The first launch's bulk marking: which countries have already been visited.
///
/// The one step that turns an empty map into the user's own. It is still skippable — somebody
/// who wants to start from nothing and fill the map as they travel is not doing it wrong.
struct OnboardingVisitedView: View {

    // MARK: - Layout

    /// Spacings of the heading above the list.
    private enum Layout {
        static let headerSpacing: CGFloat = 8
        static let headerBottomPadding: CGFloat = 8
    }

    // MARK: - Properties

    /// ISO2 codes picked so far, owned by ``OnboardingFlowView`` so they survive a step back.
    @Binding var selectedCodes: Set<String>

    // MARK: - Body

    var body: some View {

        VStack(alignment: .leading, spacing: Layout.headerSpacing) {

            Text("Where have you been?")
                .font(.largeTitle.bold())

            Text("Pick as many as you like. You can change any of them later.")
                .font(.body)
                .foregroundStyle(.secondary)

            selectionSummary

            CountryMultiSelectList(selectedCodes: $selectedCodes,
                                   searchPrompt: "Search countries")
                .listStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    /// How many are picked, or an invitation while none are.
    ///
    /// Says something in both states on purpose: a counter that appears only once you have
    /// selected something reads as an error message before it.
    @ViewBuilder
    private var selectionSummary: some View {

        Group {
            if selectedCodes.isEmpty {
                Text("Nothing selected yet")
            } else {
                Text("^[\(selectedCodes.count) country](inflect: true) selected")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.bottom, Layout.headerBottomPadding)
    }
}

#Preview {
    OnboardingVisitedView(selectedCodes: .constant(["DE", "FR"]))
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
