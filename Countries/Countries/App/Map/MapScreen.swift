//
//  MapScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import MapKit

enum MapAppearance {
    case twoD
    case threeD
}

struct MapScreen: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selected: Country?
    
    @State private var showAppearanceSheet = false
    
    @State private var appearance: MapAppearance = .twoD
    
    var body: some View {
        ZStack(alignment: .center) {
            
            switch appearance {
            case .twoD:
                FlatCountriesMapView(interactiveEnabled: true, renderMode: .aspectFit)
            case .threeD:
                GlobeMapView()
            }
            
            if let country = selected {
                Text(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "chevron.left") {
                    dismiss() // oder über Binding den Path anpassen
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "globe") {
                    showAppearanceSheet = true
                }
            }
        }
        .sheet(isPresented: $showAppearanceSheet) {
            NavigationStack {
                VStack {
                    Picker("Appearence", selection: $appearance) {
                        Text("2D").tag(MapAppearance.twoD)
                        Text("3D").tag(MapAppearance.threeD)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .padding(.horizontal, 4)
                }
                .navigationTitle("Appearance")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", systemImage: "xmark") { showAppearanceSheet = false }
                    }
                }
            }
            .presentationDetents([.fraction(0.15)])
            
        }
    }
}

#Preview {
    MapScreen()
}
