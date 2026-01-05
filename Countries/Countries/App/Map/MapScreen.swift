//
//  MapScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selected: Country?
    
    var body: some View {
        ZStack(alignment: .center) {
            
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "chevron.left") {
                    dismiss() // oder über Binding den Path anpassen
                }
            }
        }
    }
}

#Preview {
    MapScreen()
}
