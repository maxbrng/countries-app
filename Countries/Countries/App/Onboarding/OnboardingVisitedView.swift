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
        /// Gap between the mode picker and what it switches.
        static let pickerBottomPadding: CGFloat = 12
        /// Corner radius of the map, so it reads as a panel rather than as a cut-off image.
        static let mapCornerRadius: CGFloat = 20
    }

    /// How the user is picking countries.
    private enum PickingMode: Hashable, CaseIterable {

        /// A searchable list, grouped by continent.
        case list

        /// The world map, tapped country by country.
        case map

        /// Name shown in the picker.
        var title: LocalizedStringKey {
            switch self {
            case .list: return "List"
            case .map: return "Map"
            }
        }
    }

    // MARK: - Properties

    /// ISO2 codes picked so far, owned by ``OnboardingFlowView`` so they survive a step back.
    @Binding var selectedCodes: Set<String>

    /// Whether the list or the map is on screen.
    @State private var mode: PickingMode = .list

    /// The map's own single selection, used here only as a signal that a country was tapped.
    ///
    /// Each tap is turned into a toggle and the selection is cleared again, so tapping the
    /// same country twice adds it and removes it rather than doing nothing the second time.
    @State private var tappedCountry: Country?

    /// What the picking map is asked to do: tappable and pannable, but unlabelled.
    ///
    /// Labels would compete with the fills that say what has been picked, and this screen is
    /// about the fills.
    private static let pickingDetail = MapDetailRequest(selectionEnabled: true,
                                                        interactiveEnabled: true,
                                                        labelsEnabled: false)

    /// Shown unfiltered: the map has no status filter during the first launch.
    @State private var mapFilter: CountryStatusFilter = .all

    // MARK: - Body

    var body: some View {

        VStack(alignment: .leading, spacing: Layout.headerSpacing) {

            Text("Where have you been?")
                .font(.largeTitle.bold())

            Text("Pick as many as you like. You can change any of them later.")
                .font(.body)
                .foregroundStyle(.secondary)

            selectionSummary

            Picker("How to pick", selection: $mode) {
                ForEach(PickingMode.allCases, id: \.self) { pickingMode in
                    Text(pickingMode.title).tag(pickingMode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, Layout.pickerBottomPadding)

            switch mode {
            case .list:
                CountryMultiSelectList(selectedCodes: $selectedCodes,
                                       searchPrompt: "Search countries")
                    .listStyle(.plain)
            case .map:
                mapPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Map

    /// The world map, where a tap adds or removes a country.
    ///
    /// The map keeps its own single selection, which is what its hit-testing produces. Here
    /// that is read as "this one was tapped" and turned into a toggle, then cleared — a map
    /// that highlighted one country at a time would be answering a different question from
    /// the one this screen asks.
    private var mapPicker: some View {

        FlatMapView(detail: Self.pickingDetail,
                    focusesSelectedCountry: false,
                    pendingVisitedISO2: Set(selectedCodes.map { $0.lowercased() }),
                    selectedCountry: $tappedCountry,
                    filter: $mapFilter)
            .clipShape(RoundedRectangle(cornerRadius: Layout.mapCornerRadius,
                                        style: .continuous))
            .onChange(of: tappedCountry) { _, country in

                guard let country else { return }

                toggle(country.iso2)
                tappedCountry = nil
            }
    }

    // MARK: - Actions

    /// Adds a code to the selection, or removes it when it is already in.
    ///
    /// - Parameter iso2: ISO2 code of the tapped country.
    private func toggle(_ iso2: String) {

        if selectedCodes.contains(iso2) {
            selectedCodes.remove(iso2)
            return
        }

        selectedCodes.insert(iso2)
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
