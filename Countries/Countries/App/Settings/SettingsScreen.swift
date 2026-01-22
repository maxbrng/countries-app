//
//  SettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

struct SettingsScreen: View {
    
    @AppStorage("selectedMockUser") private var selectedMockUser: Int = 0
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false
    
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("General") {
                Toggle("Only show UN countries", isOn: $showOnlyUNMembers)
                Picker("Mock profile", selection: $selectedMockUser) {
                    Text("User 1").tag(0)
                    Text("User 2").tag(1)
                    Text("User 3").tag(2)
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMockUser) { _, _ in
                    do {
                        try CountrySeeder.applyMockProfile(in: modelContext)
                    } catch {
                        // Optionally handle error (e.g., show alert). For now, just log.
                        print("Failed to apply mock profile: \(error)")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            _ = selectedMockUser
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}

