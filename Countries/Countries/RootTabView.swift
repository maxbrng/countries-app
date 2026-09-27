//
//  RootTabView.swift
//  Countries
//
//  Created by Max Breuning on 03.12.25.
//

import SwiftUI

/// Destinations pushed onto the shared navigation path of the first tab.
enum AppRoute: Hashable {
    /// The full country list, pushed from the main screen's country card.
    case fullCountryList
    /// The interactive map screen.
    case mapScreen
    /// The settings screen.
    case settings
}

/// The tabs of the app, used as the ``TabView`` selection.
enum AppTab: Hashable {
    /// Dashboard and everything pushed from it.
    case countries
    /// The trips list.
    case trips
    /// The full country list in the search role.
    case search
}

/// Root of the app: Countries, Trips, and the country list in the search role.
///
/// - Note: Only the first tab owns a ``NavigationPath``; ``AppRoute`` is resolved there.
struct RootTabView: View {

    // MARK: - Properties

    /// The visible tab. Held here so the dashboard's trip card can switch to ``AppTab/trips``
    /// instead of pushing a second copy of the list onto the first tab's stack.
    @State private var selectedTab: AppTab = .countries

    /// Shared navigation path of the first tab, handed to ``MainScreen`` and to the map.
    @State private var path = NavigationPath()

    /// Owned here so the field belongs to the tab bar. Inside ``CountriesList`` it jumped.
    @State private var countrySearch = ""

    /// Search text of the pushed full list, kept apart from the search tab's.
    @State private var fullListSearch = ""

    // MARK: - Body

    var body: some View {

        TabView(selection: $selectedTab) {
            Tab("Countries", systemImage: "globe.europe.africa.fill", value: AppTab.countries) {
                NavigationStack(path: $path) {
                    MainScreen(path: $path, onOpenTrips: { selectedTab = .trips })
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                // From the path, not from `onAppear`, which fires after the transition.
                .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
            }

            Tab("Trips", systemImage: "suitcase.rolling.fill", value: AppTab.trips) {
                NavigationStack {
                    TripsListView()
                }
            }

            Tab("All Countries", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack {
                    // Inside the stack, so the field belongs to the tab bar.
                    CountriesList(searchText: $countrySearch)
                        .searchable(text: $countrySearch)
                }
            }
        }
        // Without this, iOS 27 folds the search tab into the pill and its field to the top.
        .tabViewSearchActivation(.searchTabSelection)
    }

    // MARK: - Destinations

    /// Resolves an ``AppRoute`` to its screen.
    ///
    /// - Parameter route: The route that was appended to ``path``.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .fullCountryList:
            CountriesList(searchText: $fullListSearch)
                .searchable(text: $fullListSearch)
        case .mapScreen:
            MapControllerRepresentable(path: $path)
                .ignoresSafeArea()
        case .settings:
            SettingsScreen()
        }
    }
}

#Preview {
    RootTabView()
}
