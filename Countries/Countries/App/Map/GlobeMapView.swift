//
//  GlobeMapView.swift
//  Countries
//
//  Created by Max Breuning on 05.01.26.
//


import SwiftUI
import MapKit

struct GlobeMapView: View {
    // Startet direkt im Weltraum-Zoom
    @State private var position: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            distance: 30_000_000, // 30.000 km – das erzwingt den Globus
            heading: 0,
            pitch: 0
        )
    )
    
    var body: some View {
        Map(position: $position) {
            // Hier kannst du deine Pins setzen
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        // Optional: Ein Button, um sofort zum Globus zurückzukehren
        .safeAreaInset(edge: .bottom) {
            Button("Reset to Globe") {
                withAnimation(.spring) {
                    position = .camera(MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                        distance: 30_000_000
                    ))
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
