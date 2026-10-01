//
//  TripFormattingTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import Testing
@testable import Countries

/// Covers how a trip's length is counted and how trips are ordered.
///
/// The day count is the kind of arithmetic that looks obvious and is wrong at every edge: a
/// same-day trip is one day and not zero, a trip with one date missing must not guess the
/// other end, and a range crossing a daylight saving change is not 23 or 25 hours of days.
@MainActor
struct TripFormattingTests {

    // MARK: - Helpers

    /// Builds a date from year, month and day in the current calendar.
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {

        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        let date = Calendar.current.date(from: components)

        return try #require(date)
    }

    // MARK: - Duration

    @Test func test_durationInDays_sameDay_isOneDay() throws {

        // Arrange
        let day = try date(2026, 3, 12)
        let trip = Trip(startDate: day, endDate: day)

        // Act / Assert: a day trip lasts a day, not nothing.
        #expect(TripFormatting.durationInDays(for: trip) == 1)
    }

    @Test func test_durationInDays_countsBothEnds() throws {

        let trip = Trip(startDate: try date(2026, 3, 12), endDate: try date(2026, 3, 14))

        #expect(TripFormatting.durationInDays(for: trip) == 3)
    }

    @Test func test_durationInDays_onlyAStartDate_isOneDay() throws {

        let trip = Trip(startDate: try date(2026, 3, 12), endDate: nil)

        // The other end is unknown; the least the data supports is one day.
        #expect(TripFormatting.durationInDays(for: trip) == 1)
    }

    @Test func test_durationInDays_onlyAnEndDate_isOneDay() throws {

        let trip = Trip(startDate: nil, endDate: try date(2026, 3, 12))

        #expect(TripFormatting.durationInDays(for: trip) == 1)
    }

    @Test func test_durationInDays_noDates_isNil() {

        #expect(TripFormatting.durationInDays(for: Trip()) == nil)
    }

    @Test func test_durationInDays_timesOfDayDoNotChangeIt() throws {

        let earlyStart = Calendar.current.date(bySettingHour: 1, minute: 0, second: 0,
                                               of: try date(2026, 3, 12))
        let lateEnd = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0,
                                            of: try date(2026, 3, 13))
        let trip = Trip(startDate: try #require(earlyStart), endDate: try #require(lateEnd))

        // Counted in calendar days, not in elapsed hours.
        #expect(TripFormatting.durationInDays(for: trip) == 2)
    }

    @Test func test_durationInDays_acrossADaylightSavingChange_staysAWholeNumberOfDays() throws {

        // Central European summer time starts on 29 March 2026; that day is 23 hours long.
        let trip = Trip(startDate: try date(2026, 3, 28), endDate: try date(2026, 3, 30))

        #expect(TripFormatting.durationInDays(for: trip) == 3)
    }

    @Test func test_durationInDays_invertedRange_isStillPositive() throws {

        // The editor prevents this, but stored data from elsewhere need not respect it.
        let trip = Trip(startDate: try date(2026, 3, 14), endDate: try date(2026, 3, 12))

        #expect(TripFormatting.durationInDays(for: trip) == 3)
    }

    // MARK: - Ordering

    @Test func test_sortedNewestFirst_datedTripsComeBeforeUndatedOnes() throws {

        let dated = Trip(title: "Dated", startDate: try date(2020, 1, 1))
        let undated = Trip(title: "Undated")

        let sorted = TripFormatting.sortedNewestFirst([undated, dated])

        #expect(sorted.first?.title == "Dated")
    }

    @Test func test_sortedNewestFirst_newerTripComesFirst() throws {

        let older = Trip(title: "Older", startDate: try date(2024, 5, 1))
        let newer = Trip(title: "Newer", startDate: try date(2026, 5, 1))

        let sorted = TripFormatting.sortedNewestFirst([older, newer])

        #expect(sorted.first?.title == "Newer")
    }

    // MARK: - Title

    @Test func test_displayTitle_blankTitle_fallsBackToThePlaceholder() {

        let trip = Trip(title: "   ")

        #expect(TripFormatting.displayTitle(for: trip) == String(localized: "Untitled trip"))
    }

    @Test func test_displayTitle_trimsSurroundingWhitespace() {

        let trip = Trip(title: "  Summer in Spain  ")

        #expect(TripFormatting.displayTitle(for: trip) == "Summer in Spain")
    }
}
