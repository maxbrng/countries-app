//
//  RootTabView.swift
//  Countries
//
//  Created by Max Breuning on 03.12.25.
//

import SwiftUI
import MapKit
import Foundation

import Foundation

// Conforms to Hashable so it can be used with NavigationPath and navigationDestination.
public enum AppRoute: Hashable {
//    case countryDetail(country: Country)
    case fullCountryList
    case mapScreen
}

struct RootTabView: View {

    @State private var path = NavigationPath()
    
    var body: some View {
        
        TabView {
            NavigationStack(path: $path) {
                MainScreen(path: $path)
                    .navigationDestination(for: AppRoute.self) { (route: AppRoute) in
                        destination(for: route)
                    }
            }
            .tabItem {
                Label("Countries", systemImage: "globe.europe.africa.fill")
            }
            
            // hierfür ne separated route?
            NavigationStack {
                DiscoverScreen(path: $path)
            }
            .tabItem {
                Label("Discover", systemImage: "binoculars.fill")
            }
        }
    }
    
    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .fullCountryList:
            FullCountriesList(path: $path)
        case .mapScreen:
            MapScreen()
        }
    }
}

#Preview {
    RootTabView()
}
