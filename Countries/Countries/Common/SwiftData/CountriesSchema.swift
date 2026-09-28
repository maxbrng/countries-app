//
//  CountriesSchema.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData

/// The shape of the store as it ships in 1.0.
///
/// Declared as a ``VersionedSchema`` before the first release rather than after it, because the
/// version identifier is what a later migration is measured against. A store written by an
/// unversioned container cannot be told apart from one written by any other unversioned
/// container, so the first migration would have nothing to migrate *from*.
///
/// From 1.0 on, every change to a stored property is a migration: a new ``VersionedSchema``
/// here, a ``MigrationStage`` in ``CountriesMigrationPlan``, and — because this store holds the
/// only copy of data the user typed — a backup taken before it runs.
///
/// ## The fields
///
/// This list is the record of what 1.0 stores. It is kept here, next to the version identifier,
/// so it cannot drift away from the models it describes.
///
/// ### ``Country``
/// `iso2` (unique), `iso3`, `nameEnglish`, `nativeName`, `continent`, `capital`, `phoneCodes`,
/// `currencies`, `languages`, `status`, `notes`, `isUNMember`, `dataHadSourceTranslations`,
/// `travelTags`, `climateTags`, `costLevel`, `safetyLevel`, `trips` (relationship),
/// `translationsData` (external storage).
///
/// ### ``Trip``
/// `title`, `startDate`, `endDate`, `notes`, `countries` (relationship, nullifying, inverse of
/// ``Country/trips``).
///
/// ## Deliberately absent in 1.0
///
/// Three things were considered and left out. They are recorded here rather than forgotten,
/// because each of them would be a migration, and because a placeholder field that nothing
/// writes is worse than no field at all — it has to be migrated too, and it teaches a reader
/// that the schema means less than it says.
///
/// - **Several visits to one country.** ``Country/status`` is a single value, so a country is
///   visited or not. A second visit is a second ``Trip`` that mentions the same country, which
///   is what ``Trip/countries`` already expresses. A per-visit record would be a new model.
/// - **Cities.** No model, no field. A trip is a set of countries and a date range. Cities
///   would need their own model, their own data source and their own map layer.
/// - **Time zones.** Not stored, in any form. Trip dates are plain ``Date`` values read in the
///   user's current calendar, which is correct for a diary and wrong for anything that has to
///   agree with a booking. If that changes, the field is an IANA identifier
///   (`Europe/Berlin`), never a UTC offset — offsets move twice a year.
nonisolated enum CountriesSchemaV1: VersionedSchema {

    /// The version a 1.0 store is stamped with.
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// Every model in the store. A model missing here is a model SwiftData will not see.
    static var models: [any PersistentModel.Type] { [Country.self, Trip.self] }
}

/// How the store gets from one schema version to the next.
///
/// Empty in 1.0, and that is the point: it exists so that the container is already migrating
/// when the first real stage is added, rather than being switched to a migrating container at
/// the same moment as the first schema change.
nonisolated enum CountriesMigrationPlan: SchemaMigrationPlan {

    /// Every schema version, oldest first.
    static var schemas: [any VersionedSchema.Type] { [CountriesSchemaV1.self] }

    /// The steps between them. None yet — 1.0 is the first version.
    static var stages: [MigrationStage] { [] }
}
