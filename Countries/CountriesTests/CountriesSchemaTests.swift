//
//  CountriesSchemaTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Guards the shape of the 1.0 store.
///
/// These are not tests of behaviour; they are a tripwire. A model added to the app but not to
/// ``CountriesSchemaV1`` would simply not be persisted, and a version identifier bumped by
/// accident would make a later migration start from the wrong place. Neither shows up until a
/// user's data is already in the wrong shape, which is the one failure this app cannot undo.
@MainActor
struct CountriesSchemaTests {

    @Test
    func test_versionIdentifier_isTheOneTheFirstReleaseShipped() {

        // Arrange & Act
        let version = CountriesSchemaV1.versionIdentifier

        // Assert
        // Changing this means the store on a user's device is no longer what this schema
        // describes, which is a migration, not an edit.
        #expect(version == Schema.Version(1, 0, 0))
    }

    @Test
    func test_models_containEveryPersistedType() {

        // Arrange & Act
        let names = CountriesSchemaV1.models.map { String(describing: $0) }.sorted()

        // Assert
        #expect(names == ["Country", "Trip"])
    }

    @Test
    func test_migrationPlan_startsAtTheFirstSchemaAndHasNoStagesYet() {

        // Arrange & Act
        let schemas = CountriesMigrationPlan.schemas.map { String(describing: $0) }

        // Assert
        #expect(schemas == ["CountriesSchemaV1"])
        #expect(CountriesMigrationPlan.stages.isEmpty)
    }

    @Test
    func test_container_opensWithTheVersionedSchemaAndThePlan() throws {

        // Arrange
        let schema = Schema(versionedSchema: CountriesSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // Act
        let container = try ModelContainer(for: schema,
                                           migrationPlan: CountriesMigrationPlan.self,
                                           configurations: configuration)

        // Assert
        // Opening it is the assertion: a schema the plan cannot account for throws here.
        #expect(container.schema.version == Schema.Version(1, 0, 0))
    }
}
