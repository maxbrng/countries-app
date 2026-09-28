//
//  OnboardingWelcomeView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI

/// What the app is for, in one screen.
///
/// Three lines, not a tour. The map behind them is the actual argument, so it gets the room.
struct OnboardingWelcomeView: View {

    // MARK: - Layout

    /// Sizes of the welcome screen.
    private enum Layout {
        /// Gap between the map and the text block.
        static let sectionSpacing: CGFloat = 32
        /// Gap between the headline and the sentence under it.
        static let textSpacing: CGFloat = 12
        /// Height of the map preview.
        static let mapHeight: CGFloat = 220
        static let mapCornerRadius: CGFloat = 20
    }

    // MARK: - Properties

    /// Nothing is selectable here, and the flow owns no selection, so both bindings are local
    /// and constant — the map is a picture at this point, not a control.
    @State private var selectedCountry: Country?

    @State private var filter: CountryStatusFilter = .all

    // MARK: - Body

    var body: some View {

        VStack(spacing: Layout.sectionSpacing) {

            Spacer(minLength: 0)

            FlatMapView(detail: .preview,
                        aspectFitStartsZoomed: false,
                        selectedCountry: $selectedCountry,
                        filter: $filter)
                .frame(height: Layout.mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: Layout.mapCornerRadius,
                                            style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: Layout.textSpacing) {

                Text("A world map you colour in")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Mark the countries you have been to and the ones you want to see. Everything stays on this device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
