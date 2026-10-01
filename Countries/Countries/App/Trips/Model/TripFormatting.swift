//
//  TripFormatting.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import Foundation

/// Shared display helpers for ``Trip``, used by the list and the editor so both render a trip
/// the same way.
enum TripFormatting {

    /// Sorts trips newest first, with undated trips last.
    ///
    /// Used by both the trips list and the dashboard, so the two can never disagree about
    /// what "recent" means.
    ///
    /// - Parameter trips: The trips to sort, in any order.
    /// - Returns: Dated trips by descending start date, then undated ones by title.
    static func sortedNewestFirst(_ trips: [Trip]) -> [Trip] {

        trips.sorted { lhs, rhs in
            switch (lhs.startDate, rhs.startDate) {
            case let (left?, right?): return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return displayTitle(for: lhs) < displayTitle(for: rhs)
            }
        }
    }

    /// Title to show for a trip, falling back to a placeholder while the user has given none.
    ///
    /// - Parameter trip: The trip to label.
    /// - Returns: The trimmed title, or a localized placeholder when it is empty.
    static func displayTitle(for trip: Trip) -> String {

        let trimmed = trip.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return String(localized: "Untitled trip")
        }
        return trimmed
    }

    /// Length of a trip in days, counting both the first and the last day.
    ///
    /// A trip that starts and ends on the same day is one day long, not zero, because that is
    /// what a traveller means by "a day trip". A trip with only one of the two dates set is
    /// also one day: the other end is unknown, and guessing it would be worse than saying the
    /// least the data supports.
    ///
    /// - Parameter trip: The trip to measure.
    /// - Returns: The inclusive number of days, or `nil` when the trip carries no dates.
    static func durationInDays(for trip: Trip) -> Int? {

        guard let anyDate = trip.startDate ?? trip.endDate else { return nil }

        let otherDate = trip.endDate ?? trip.startDate ?? anyDate
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: min(anyDate, otherDate))
        let last = calendar.startOfDay(for: max(anyDate, otherDate))

        guard let elapsed = calendar.dateComponents([.day], from: first, to: last).day else {
            return nil
        }

        return elapsed + 1
    }

    /// Date range of a trip as one line.
    ///
    /// - Parameter trip: The trip to describe.
    /// - Returns: `"12 Mar 2026 – 26 Mar 2026"` when both ends are set, a single date when only
    ///   one is, and `nil` when the trip carries no dates at all.
    static func dateRange(for trip: Trip) -> String? {
        dateRange(start: trip.startDate, end: trip.endDate)
    }

    /// Date range of the two given days as one line.
    ///
    /// - Parameters:
    ///   - start: First day, or `nil`.
    ///   - end: Last day, or `nil`.
    /// - Returns: A formatted range, a single date, or `nil` when both are `nil`.
    static func dateRange(start: Date?, end: Date?) -> String? {

        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()

        switch (start, end) {
        case let (start?, end?):
            // An inverted range is prevented in the editor, so it is not handled separately.
            return "\(start.formatted(style)) – \(end.formatted(style))"
        case let (start?, nil):
            return start.formatted(style)
        case let (nil, end?):
            return end.formatted(style)
        case (nil, nil):
            return nil
        }
    }
}
