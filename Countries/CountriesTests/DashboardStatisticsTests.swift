//
//  DashboardStatisticsTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import Testing
@testable import Countries

/// Covers the three figures of the dashboard at their edges.
///
/// None of these states shows up while using the app normally: an empty database, the very
/// first country, the very last one. Each of them produced a number that was either a division
/// by zero or a claim the data does not support, so each is pinned here rather than left to be
/// noticed by a user who has just marked their first country and is told they have seen 0 % of
/// the world.
struct DashboardStatisticsTests {

    // MARK: - Nothing to measure

    @Test
    func test_worldShare_withoutAnyCountries_isUnmeasurable() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 0,
                                             countriesTotal: 0,
                                             continentsVisited: 0,
                                             continentsTotal: 0)

        // Assert
        #expect(statistics.worldShare == .unmeasurable)
        #expect(statistics.gaugeProgress == 0)
    }

    @Test
    func test_gaugeProgress_withoutAnyCountries_isFiniteRatherThanNaN() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 0,
                                             countriesTotal: 0,
                                             continentsVisited: 0,
                                             continentsTotal: 0)

        // Assert
        // A zero denominator would give NaN here, which Gauge renders as an empty ring and
        // Int(_:) traps on.
        #expect(statistics.gaugeProgress.isFinite)
    }

    // MARK: - Nothing visited

    @Test
    func test_worldShare_withNothingVisited_showsNoPercentage() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 0,
                                             countriesTotal: 250,
                                             continentsVisited: 0,
                                             continentsTotal: 7)

        // Assert
        #expect(statistics.worldShare == .nothingVisited)
    }

    // MARK: - Rounding

    @Test
    func test_worldShare_withTheFirstCountryOfMany_reportsOnePercentInsteadOfZero() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 1,
                                             countriesTotal: 250,
                                             continentsVisited: 1,
                                             continentsTotal: 7)

        // Assert
        // 0.4 % rounds to zero, which is indistinguishable from having visited nothing.
        #expect(statistics.worldShare == .percentage(1))
    }

    @Test
    func test_worldShare_withOneCountryMissing_staysBelowAHundredPercent() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 249,
                                             countriesTotal: 250,
                                             continentsVisited: 7,
                                             continentsTotal: 7)

        // Assert
        // 99.6 % rounds to a hundred, which would claim a completed world that is not complete.
        #expect(statistics.worldShare == .percentage(99))
    }

    @Test
    func test_worldShare_atHalfTheWorld_reportsFiftyPercent() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 98,
                                             countriesTotal: 195,
                                             continentsVisited: 5,
                                             continentsTotal: 7)

        // Assert
        #expect(statistics.worldShare == .percentage(50))
    }

    // MARK: - Everything visited

    @Test
    func test_worldShare_withEveryCountryVisited_changesTheUnitInsteadOfReportingAHundred() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: 195,
                                             countriesTotal: 195,
                                             continentsVisited: 7,
                                             continentsTotal: 7)

        // Assert
        #expect(statistics.worldShare == .everything)
        #expect(statistics.gaugeProgress == 1)
    }

    // MARK: - Impossible input

    @Test
    func test_init_withMoreVisitedThanTotal_clampsInsteadOfExceedingTheGauge() {

        // Arrange & Act
        // Reachable while a filter is being applied and the two queries disagree for a frame.
        let statistics = DashboardStatistics(countriesVisited: 300,
                                             countriesTotal: 195,
                                             continentsVisited: 9,
                                             continentsTotal: 7)

        // Assert
        #expect(statistics.countriesVisited == 195)
        #expect(statistics.continentsVisited == 7)
        #expect(statistics.gaugeProgress == 1)
        #expect(statistics.worldShare == .everything)
    }

    @Test
    func test_init_withNegativeCounts_readsAsNothingVisited() {

        // Arrange & Act
        let statistics = DashboardStatistics(countriesVisited: -3,
                                             countriesTotal: 195,
                                             continentsVisited: -1,
                                             continentsTotal: 7)

        // Assert
        #expect(statistics.countriesVisited == 0)
        #expect(statistics.continentsVisited == 0)
        #expect(statistics.worldShare == .nothingVisited)
    }
}
