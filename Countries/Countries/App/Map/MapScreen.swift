//
//  MapScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    @State private var selected: Country?
    
    var body: some View {
        ZStack(alignment: .center) {
//            CountriesMapView(selectedCountry: $selected)
            StaticCountriesMapView(interactiveEnabled: true, renderMode: .aspectFit)
            
            if let country = selected {
                Text(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    MapScreen()
}
