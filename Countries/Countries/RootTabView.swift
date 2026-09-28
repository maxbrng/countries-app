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
    /// The trips list, pushed from the main screen's trip card.
    case tripsList
    /// The interactive map screen.
    case mapScreen
    /// The settings screen.
    case settings
}

/// Root of the app: Countries, Discover, Trips, and the country list in the search role.
///
/// - Note: Only the first tab owns a ``NavigationPath``; ``AppRoute`` is resolved there.
struct RootTabView: View {

    // MARK: - Properties

    /// Shared navigation path of the first tab, handed to ``MainScreen`` and to the map.
    @State private var path = NavigationPath()

    /// Owned here so the field belongs to the tab bar. Inside ``CountriesList`` it jumped.
    @State private var countrySearch = ""

    /// Search text of the pushed full list, kept apart from the search tab's.
    @State private var fullListSearch = ""

    // MARK: - Body

    var body: some View {

        TabView {
            Tab("Countries", systemImage: "globe.europe.africa.fill") {
                NavigationStack(path: $path) {
                    MainScreen(path: $path)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                // From the path, not from `onAppear`, which fires after the transition.
                .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
            }

            Tab("Discover", systemImage: "binoculars.fill") {
                NavigationStack {
                    DiscoverScreen()
                }
            }

            Tab("Trips", systemImage: "suitcase.rolling.fill") {
                NavigationStack {
                    TripsListView()
                }
            }

            Tab("All countries", systemImage: "magnifyingglass", role: .search) {
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
        case .tripsList:
            TripsListView()
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
