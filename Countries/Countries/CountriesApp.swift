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

@main
struct CountriesApp: App {
    
    private let sharedModelContainer: ModelContainer = {
        
        let schema = Schema([Country.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        
        WindowGroup {
            RootTabView()
                .task {
                    do {
                        try CountrySeeder.seedIfNeeded(in: sharedModelContainer.mainContext)
                        logger.info("App seeding completed (or skipped).")
                    } catch {
                        logger.error("App seeding failed: \((error as NSError).localizedDescription, privacy: .public)")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
