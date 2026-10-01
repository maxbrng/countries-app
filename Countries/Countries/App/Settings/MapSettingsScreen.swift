//
//  MapSettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Everything about how the map looks, on a page of its own.
///
/// It holds one picker today. It is a separate screen anyway because this is where the map's
/// own appearance — its colours, and what a status looks like — is going to live, and a
/// customisation screen is not something to graft onto the settings list later.
struct MapSettingsScreen: View {

    // MARK: - Properties

    /// Which renderer the map screen opens in. Shares its key with ``MapScreenModel``.
    @AppStorage(MapAppearance.storageKey) private var mapAppearance: MapAppearance = .twoD

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Picker("Map style", selection: $mapAppearance) {
                    ForEach(MapAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("The flat map draws the countries itself. The globe puts them on Apple's satellite imagery.")
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        MapSettingsScreen()
    }
}
