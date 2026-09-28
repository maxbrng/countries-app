//
//  TripDeletion.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData

/// What deleting one trip takes with it, and what it leaves behind.
///
/// Built before the deletion so the confirmation can name both sides concretely instead of
/// warning in the abstract. The distinction is not cosmetic: a trip and a country's visited
/// status are separate records — see [C-05] — and the user has no way of knowing that unless
/// the dialog says so.
struct TripDeletionSummary {

    /// Title of the trip, already falling back to the placeholder.
    let tripTitle: String

    /// The trip's date range, or `nil` when it carries no dates.
    let dateRange: String?

    /// Whether the trip carries notes that would go with it.
    let hasNotes: Bool

    /// Names of the countries on the trip, alphabetically.
    let countryNames: [String]
}

/// Everything needed to put a deleted trip back exactly as it was.
///
/// The countries are held as references rather than as codes: deleting a trip nullifies the
/// relationship but never touches a ``Country``, so those objects are still valid afterwards
/// and can simply be reattached.
struct TripSnapshot {

    let title: String?
    let startDate: Date?
    let endDate: Date?
    let notes: String?
    let countries: [Country]
}

/// Deleting a trip, and undoing it.
///
/// - Note: There is no trash bin in 1.0, on purpose. The undo window is the safety net; a bin
///   would be a second place where trips live and a second thing to keep in sync.
@MainActor
enum TripDeletion {

    /// Describes what deleting `trip` would do.
    ///
    /// - Parameter trip: The trip about to be deleted.
    /// - Returns: The two sides of the deletion, ready to be rendered.
    static func summary(for trip: Trip) -> TripDeletionSummary {

        TripDeletionSummary(
            tripTitle: TripFormatting.displayTitle(for: trip),
            dateRange: TripFormatting.dateRange(for: trip),
            hasNotes: !(trip.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty,
            countryNames: trip.countries.map(\.nameEnglish).sorted()
        )
    }

    /// Captures everything about `trip` that a restore would need.
    ///
    /// - Parameter trip: The trip about to be deleted.
    /// - Returns: A snapshot that survives the deletion.
    static func snapshot(of trip: Trip) -> TripSnapshot {

        TripSnapshot(title: trip.title,
                     startDate: trip.startDate,
                     endDate: trip.endDate,
                     notes: trip.notes,
                     countries: trip.countries)
    }

    /// Deletes `trip` and saves.
    ///
    /// - Parameters:
    ///   - trip: The trip to delete.
    ///   - context: The context holding it.
    /// - Returns: The snapshot taken immediately before, for the undo window.
    @discardableResult
    static func delete(_ trip: Trip, in context: ModelContext) -> TripSnapshot {

        let snapshot = snapshot(of: trip)

        context.delete(trip)
        try? context.save()

        return snapshot
    }

    /// Recreates a deleted trip from its snapshot.
    ///
    /// The restored trip is a new object with a new identity; everything the user can see about
    /// it is the same, which is what "restores the trip completely" means here. Reviving the
    /// original object is not possible once SwiftData has deleted it.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot taken at deletion time.
    ///   - context: The context to insert into.
    /// - Returns: The restored trip.
    @discardableResult
    static func restore(_ snapshot: TripSnapshot, in context: ModelContext) -> Trip {

        let trip = Trip(title: snapshot.title,
                        startDate: snapshot.startDate,
                        endDate: snapshot.endDate,
                        countries: snapshot.countries,
                        notes: snapshot.notes)

        context.insert(trip)
        try? context.save()

        return trip
    }
}
