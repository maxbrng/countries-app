//
//  CountriesApp.swift
//  Countries
//
//  Created by Max Breuning on 03.12.25.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries", category: "App")

/// App entry point: builds the shared `ModelContainer` and bootstraps the stored data
/// before the first screen needs it.
@main
struct CountriesApp: App {

    // MARK: - Properties

    /// The single on-disk container for ``Country``, ``Trip`` and ``UserPreferences``.
    ///
    /// - Note: The app cannot run without its store, so a failure here is fatal by design.
    private let sharedModelContainer: ModelContainer = {

        let schema = Schema([
                Country.self,
                Trip.self,
                UserPreferences.self
            ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Scene

    var body: some Scene {

        WindowGroup {
            RootTabView()
                .task {
                    do {
                        let context = sharedModelContainer.mainContext
                        try CountrySeeder.seedIfNeeded(in: context)
                        // Must exist before Discover or the algorithm settings are opened.
                        try PreferencesService.loadOrCreate(in: context)
                        logger.info("App bootstrap completed.")
                    } catch {
                        logger.error(
                            "App bootstrap failed: \((error as NSError).localizedDescription, privacy: .public)"
                        )
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
