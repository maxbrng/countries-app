//
//  Trip.swift
//  Countries
//
//  Created by Max Breuning on 19.01.26.
//

import Foundation
import SwiftData

/// A journey the user took, grouping the countries visited on it.
///
/// A country may belong to several trips. The relationship nullifies on delete, so removing a
/// trip never removes the countries it pointed at.
///
/// - Note: Every field is optional because the editor creates an empty trip and fills it in
///   before saving.
@Model
final class Trip {

    // MARK: - Properties

    /// Name the user gave the trip, for example "Southeast Asia 2026".
    var title: String?

    /// First day of the trip, or `nil` while no date range has been picked.
    var startDate: Date?

    /// Last day of the trip, inclusive, or `nil` while no date range has been picked.
    var endDate: Date?

    /// Free-form notes.
    var notes: String?

    /// Countries visited on this trip.
    @Relationship(deleteRule: .nullify, inverse: \Country.trips)
    var countries: [Country]

    // MARK: - Init

    /// Creates a trip.
    ///
    /// - Parameters:
    ///   - title: Name of the trip. Defaults to `nil`.
    ///   - startDate: First day. Defaults to `nil`.
    ///   - endDate: Last day, inclusive. Defaults to `nil`.
    ///   - countries: Countries visited on the trip. Defaults to empty.
    ///   - notes: Free-form notes. Defaults to `nil`.
    init(title: String? = nil,
         startDate: Date? = nil,
         endDate: Date? = nil,
         countries: [Country] = [],
         notes: String? = nil) {

        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.countries = countries
        self.notes = notes
    }
}
