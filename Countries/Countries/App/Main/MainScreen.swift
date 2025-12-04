//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit

struct MainScreen: View {
    @StateObject private var viewModel = CountriesViewModel()
    @State private var showFullMap = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )

    var body: some View {
        
        List {
            Button {
                showFullMap = true
            } label: {
                CountryMapView(
                    states: $viewModel.states,
                    selectedCountry: viewModel.selectedCountry,
                    isInteractive: false,
                    onTapCountry: nil,
                    initialRegion: mapRegion,
                    resourceName: "countries",
                    resourceExtension: "geojson"
                    , resourceSubdirectory: "resources/assets"
                )
                .frame(height: 200)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            }
        }
        .navigationTitle("Your Journey")
        .sheet(isPresented: $showFullMap) {
            FullMapScreen(viewModel: viewModel)
        }
    }
}

#Preview {
    MainScreen()
}
