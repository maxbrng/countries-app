//
//  MapAppearancePanelView.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//


import SwiftUI

struct MapAppearancePanelView: View {

    @Binding var appearance: MapAppearance
    let onClose: () -> Void

    var body: some View {
        
        NavigationStack {
            
            VStack {
                Picker("Appearance", selection: $appearance) {
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
                    Button("Done", systemImage: "xmark") {
                        onClose()
                    }
                }
            }
        }
    }
}
