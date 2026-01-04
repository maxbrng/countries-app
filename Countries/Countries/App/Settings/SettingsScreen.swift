//
//  SettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

struct SettingsScreen: View {
    
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

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
