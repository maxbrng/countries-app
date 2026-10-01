//
//  TripDraft.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import Foundation
import SwiftData

/// What a trip editor was opened for.
///
/// - Note: A plain `Trip?` could not express this, because `.sheet(item:)` already reads `nil`
///   as "no sheet".
enum TripEditorSubject: Identifiable {

    /// A trip that does not exist yet.
    case new

    /// An existing trip, to be edited in place.
    case existing(Trip)

    /// Identity of the edited trip, or `nil` while creating a new one.
    var id: PersistentIdentifier? {
        switch self {
        case .new: nil
        case .existing(let trip): trip.persistentModelID
        }
    }
}

/// The editable state of a trip, held by ``TripEditorView`` and written to the store on save.
///
/// `Equatable`, which is what lets cancel tell "nothing changed" from "changed".
struct TripDraft: Equatable {

    /// Title as typed, trimmed only when it is written back.
    var title: String

    /// Whether the trip carries a date range at all.
    var hasDates: Bool

    /// First day; only meaningful while ``hasDates`` is `true`.
    var startDate: Date

    /// Last day, inclusive; only meaningful while ``hasDates`` is `true`.
    var endDate: Date

    /// ISO2 codes of the assigned countries, uppercase as stored on ``Country``.
    var countryCodes: Set<String>

    /// Free-form notes as typed.
    var notes: String

    /// Builds the draft an editor starts from.
    ///
    /// - Parameter subject: What the editor was opened for.
    init(subject: TripEditorSubject) {

        switch subject {
        case .new:
            let today = Date.now
            self.init(title: "", hasDates: false, startDate: today, endDate: today,
                      countryCodes: [], notes: "")

        case .existing(let trip):
            let today = Date.now
            self.init(title: trip.title ?? "",
                      hasDates: trip.startDate != nil || trip.endDate != nil,
                      startDate: trip.startDate ?? trip.endDate ?? today,
                      endDate: trip.endDate ?? trip.startDate ?? today,
                      countryCodes: Set(trip.countries.map(\.iso2)),
                      notes: trip.notes ?? "")
        }
    }

    /// Memberwise initialiser, used by ``init(subject:)``.
    private init(title: String,
                 hasDates: Bool,
                 startDate: Date,
                 endDate: Date,
                 countryCodes: Set<String>,
                 notes: String) {

        self.title = title
        self.hasDates = hasDates
        self.startDate = startDate
        self.endDate = endDate
        self.countryCodes = countryCodes
        self.notes = notes
    }
}
