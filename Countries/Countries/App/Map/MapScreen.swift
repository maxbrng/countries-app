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
        ZStack(alignment: .bottom) {
//            CountriesMapView(selectedCountry: $selected)
            StaticCountriesMapView()
                .frame(height: 300)
            
            if let country = selected {
                Text(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
        }
    }
}

#Preview {
    MapScreen()
}
