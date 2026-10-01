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

    /// The single on-disk container for ``Country`` and ``Trip``.
    ///
    /// Built from ``CountriesSchemaV1`` and handed a migration plan from the first release on,
    /// so the store carries a version number a later migration can start from.
    ///
    /// - Note: The app cannot run without its store, so a failure here is fatal by design.
    private let sharedModelContainer: ModelContainer = {

        let schema = Schema(versionedSchema: CountriesSchemaV1.self)
        // `.none` on purpose, not by omission: the entitlement lists CloudKit, so the default
        // `.automatic` would start syncing the moment a container identifier is filled in. The
        // privacy section claims the data stays on the device, and this is what makes that true.
        // Turning sync on means changing this line and that text together.
        let modelConfiguration = ModelConfiguration(schema: schema,
                                                    isStoredInMemoryOnly: false,
                                                    cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema,
                                      migrationPlan: CountriesMigrationPlan.self,
                                      configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Language

    /// Language chosen inside the app, applied to the whole view tree below.
    ///
    /// Read here rather than deeper down because a locale override only reaches the views
    /// underneath it, and every screen has to follow the choice - including the ones a
    /// `NavigationLink` pushes, which are siblings of the view that pushed them.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    // MARK: - Scene

    var body: some Scene {

        WindowGroup {
            RootTabView()
                .environment(\.locale, appLanguage.locale ?? Locale.autoupdatingCurrent)
                .task {
                    do {
                        // The decoded map data is a cache worth ~29 MB; it is handed back
                        // when the app is backgrounded or the system is short of memory.
                        GeoJSONLoader.startReleasingCacheUnderPressure()

                        let context = sharedModelContainer.mainContext
                        try CountrySeeder.seedIfNeeded(in: context)
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
