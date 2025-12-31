//
//  SettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        List {
            Section("General") {
                Toggle("Example setting", isOn: .constant(true))
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
