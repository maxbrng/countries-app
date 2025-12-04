//
//  RootTabView.swift
//  Countries
//
//  Created by Max Breuning on 03.12.25.
//

import SwiftUI
import MapKit

struct RootTabView: View {

    var body: some View {
        
        TabView {
            NavigationStack {
                MainScreen()
            }
            .tabItem {
                Label("Journey", systemImage: "globe.europe.africa.fill")
            }
            
            NavigationStack {
                DiscoverScreen()
            }
            .tabItem {
                Label("Discover", systemImage: "binoculars.fill")
            }
        }
    }
}

#Preview {
    RootTabView()
}
