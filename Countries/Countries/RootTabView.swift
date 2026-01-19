//
//  RootTabView.swift
//  Countries
//
//  Created by Max Breuning on 03.12.25.
//

import SwiftUI
import MapKit
import Foundation

// Conforms to Hashable so it can be used with NavigationPath and navigationDestination.
enum AppRoute: Hashable {
    //    case countryDetail(country: Country)
    case fullCountryList
    case mapScreen
    case settings
}

struct RootTabView: View {
    
    @State private var path = NavigationPath()
    
    @State private var search = ""
    
    var body: some View {
        
        TabView {
            Tab("Countries", systemImage: "globe.europe.africa.fill") {
                NavigationStack(path: $path) {
                    MainScreen(path: $path)
                        .navigationDestination(for: AppRoute.self) { (route: AppRoute) in
                            destination(for: route)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
            }
            
            Tab("Discover", systemImage: "binoculars.fill") {
                NavigationStack {
                    DiscoverScreen(path: $path)
                }
            }
            
            Tab("All Countries", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    CountriesList(path: $path)
                        .searchable(text: $search, placement: .automatic, prompt: "Search countries")
                }
            }
        }
    }
    
    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .fullCountryList:
            CountriesList(path: $path)
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
