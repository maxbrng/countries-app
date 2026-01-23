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
    
    @State private var toolbarVisibility = Visibility.visible
    
    var body: some View {
        
        TabView {
            Tab("Countries", systemImage: "globe.europe.africa.fill") {
                NavigationStack(path: $path) {
                    MainScreen(path: $path)
                        .navigationDestination(for: AppRoute.self) { (route: AppRoute) in
                            destination(for: route)
                                .onAppear { toolbarVisibility = .hidden }
                        }
                        .onAppear { toolbarVisibility = .visible }
                }
                .toolbar(toolbarVisibility, for: .tabBar)
            }
            
            Tab("Discover", systemImage: "binoculars.fill") {
                NavigationStack {
                    DiscoverScreen(path: $path)
                        .onAppear { toolbarVisibility = .visible }
                }
            }
            
            Tab("All Countries", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    CountriesList(path: $path)
                        .searchable(text: $search, placement: .automatic, prompt: "Search countries")
                        .onAppear { toolbarVisibility = .visible }
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
