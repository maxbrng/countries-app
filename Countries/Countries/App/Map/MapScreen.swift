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

struct MapScreen: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCountry: Country?
    
    @State private var showAppearanceSheet = false
    
    @State private var appearance: MapAppearance = .twoD
    
    var body: some View {
        ZStack(alignment: .center) {
            
            switch appearance {
            case .twoD:
                FlatCountriesMapView(interactiveEnabled: true,
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
                    dismiss() // oder über Binding den Path anpassen
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "globe") {
                    showAppearanceSheet = true
                }
            }
        }
        // TODO: Create Custom UIKit Sheets like Apple Maps - von Arbeit nehmen?
        .sheet(isPresented: $showAppearanceSheet) {
            appearanceSettingsSheet
        }
        .sheet(item: $selectedCountry) { country in
            CountryDetailSheet(country: country)
                .presentationDetents([.fraction(0.25)])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
        }
    }
    
    private var appearanceSettingsSheet: some View {
        
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

#Preview {
    MapScreen()
}


struct CountryDetailSheet: View {
    
    let country: Country
    
    @Environment(\.dismiss) private var dismiss
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var showDetailSheet = false
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 12) {
                    Button(action: { toggleStatus(of: country, .visited) }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Visited")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .tint(.green)

                    Button(action: { toggleStatus(of: country, .wishlist) }) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Wishlist")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .tint(.blue)
                }
                
                Button {
                    showDetailSheet = true
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Show Details")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.glass)
                .sheet(isPresented: $showDetailSheet) {
                    CountryDetailsView(country: country)
                        .padding()
                        .presentationDetents([.fraction(0.6), .fraction(0.8), .fraction(1.0)])
                        .presentationDragIndicator(.visible)
                }
            }
            .padding()
            .navigationTitle(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // TODO: Func gibts schon in nem anderen File das geht nicht!!!!
    private func toggleStatus(of country: Country, _ newStatus: CountryStatus) {
        country.status = (country.status == newStatus) ? .none : newStatus
        try? modelContext.save()
    }
    
}

