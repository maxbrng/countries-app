//
//  MapScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import MapKit
import SwiftData

enum MapAppearance {
    case twoD
    case threeD
}

struct MapView: View {
    
    @Binding var path: NavigationPath
    @Binding var selectedCountry: Country?
    @Binding var showAppearancePanel: Bool
    @Binding var appearance: MapAppearance
    
    var body: some View {
        ZStack(alignment: .center) {
            
            switch appearance {
            case .twoD:
                FlatMapView(interactiveEnabled: true,
                            initialStartZoom: 1.5,
                            selectedCountry: $selectedCountry)
            case .threeD:
                GlobeMapView(selectedCountry: $selectedCountry)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "chevron.left") {
                    path.removeLast()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "globe") {
                    showAppearancePanel = true
                }
            }
        }
    }
}
