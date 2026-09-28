//
//  PrivacyScreen.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// What the app stores and what it sends, on a page of its own.
///
/// These are facts about how the app is built, not a statement of intent, which is why they
/// read as plain sentences rather than as a policy. They sat in the middle of the settings
/// list before, where five lines of prose between two rows of controls read as an accident.
struct PrivacyScreen: View {

    // MARK: - Body

    var body: some View {
        List {
            Section {
                fact("Your countries, trips and settings are stored on this device only.")
                fact("The app has no account and no server. Nothing you enter leaves the device.")
                fact("iCloud sync is switched off, so nothing is copied to your other devices.")
                fact("Country outlines and country data are built into the app. Nothing is downloaded.")
                fact("There is no analytics, no tracking and no advertising.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content helpers

    /// One statement.
    ///
    /// - Parameter text: The statement, looked up in the string catalog.
    private func fact(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        PrivacyScreen()
    }
}
