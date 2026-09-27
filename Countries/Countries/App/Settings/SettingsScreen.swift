//
//  SettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

/// App settings, pushed from the main screen's toolbar.
///
/// - Note: The stored flags are read straight from `@AppStorage` by the screens that need
///   them, so this screen holds no view model of its own.
struct SettingsScreen: View {

    // MARK: - Properties

    /// Restricts the country list, the statistics and the map preview to UN member states.
    /// Defaults to `false`.
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    // MARK: - Body

    var body: some View {
        List {
            Section("General") {
                Toggle("Only show UN countries", isOn: $showOnlyUNMembers)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}
