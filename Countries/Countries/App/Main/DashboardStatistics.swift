//
//  DashboardStatistics.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// The three dashboard figures, and the decision of what the middle one may claim.
///
/// Kept apart from ``StatView`` because the edge cases are the whole point and none of them can
/// be seen in a normal run of the app: an empty database, the first country of two hundred and
/// fifty, and a completed world all produce a number that is either wrong or discouraging, and
/// all three are easier to pin down in a test than to reproduce by tapping.
nonisolated struct DashboardStatistics: Equatable {

    // MARK: - Nested types

    /// What the gauge is allowed to say about the share of the world that has been seen.
    enum WorldShare: Equatable {

        /// Nothing to measure against — there are no countries in the source at all.
        ///
        /// Only reachable before the seeding has run or behind a filter that matches nothing,
        /// but it is the case that would otherwise divide by zero.
        case unmeasurable

        /// Nothing visited yet. No percentage is shown: "0 %" is not a fact worth printing in
        /// large type, and the column beside it already says `0/250`.
        case nothingVisited

        /// A share between 1 and 99 per cent.
        ///
        /// Never 0 and never 100: one country out of two hundred and fifty rounds to zero, and
        /// two hundred and forty-nine out of two hundred and fifty rounds to a hundred. Both
        /// would be a lie in the direction that matters most to the person reading it.
        case percentage(Int)

        /// Every country in the source has been visited.
        case everything
    }

    // MARK: - Constants

    /// Bounds of what ``WorldShare/percentage(_:)`` may report.
    private enum Bounds {
        /// The lowest share shown once anything at all has been visited.
        static let minimumPercentage = 1
        /// The highest share shown while anything is still missing.
        static let maximumPercentage = 99
    }

    // MARK: - Properties

    /// Number of visited countries in the source.
    let countriesVisited: Int

    /// Number of countries in the source.
    let countriesTotal: Int

    /// Number of continents at least one visited country belongs to.
    let continentsVisited: Int

    /// Number of continents the source covers.
    let continentsTotal: Int

    /// What the middle column may claim.
    let worldShare: WorldShare

    /// How far the gauge is filled, always in 0…1.
    ///
    /// Taken from the exact ratio rather than from ``worldShare``, so the ring keeps moving
    /// while the printed percentage is still clamped to 1.
    let gaugeProgress: Double

    // MARK: - Life cycle

    /// Builds the figures from plain counts.
    ///
    /// - Parameters:
    ///   - countriesVisited: Visited countries in the source. Clamped to `countriesTotal`.
    ///   - countriesTotal: Countries in the source. A zero yields ``WorldShare/unmeasurable``
    ///     instead of a division.
    ///   - continentsVisited: Continents with at least one visited country.
    ///   - continentsTotal: Continents the source covers.
    init(countriesVisited: Int,
         countriesTotal: Int,
         continentsVisited: Int,
         continentsTotal: Int) {

        let total = max(0, countriesTotal)
        let visited = min(max(0, countriesVisited), total)

        self.countriesVisited = visited
        self.countriesTotal = total
        self.continentsVisited = min(max(0, continentsVisited), max(0, continentsTotal))
        self.continentsTotal = max(0, continentsTotal)

        self.gaugeProgress = total > 0 ? Double(visited) / Double(total) : 0
        self.worldShare = Self.worldShare(visited: visited, total: total, progress: gaugeProgress)
    }

    // MARK: - Helpers

    /// Decides what the gauge may print.
    ///
    /// - Parameters:
    ///   - visited: Visited countries, already clamped.
    ///   - total: Countries in the source, already clamped.
    ///   - progress: The exact ratio of the two.
    /// - Returns: The case the middle column renders.
    private static func worldShare(visited: Int, total: Int, progress: Double) -> WorldShare {

        guard total > 0 else { return .unmeasurable }
        guard visited > 0 else { return .nothingVisited }
        guard visited < total else { return .everything }

        let rounded = Int((progress * 100).rounded())

        return .percentage(min(max(rounded, Bounds.minimumPercentage), Bounds.maximumPercentage))
    }
}

// MARK: - From stored countries

@MainActor
extension DashboardStatistics {

    /// Builds the figures from the stored countries.
    ///
    /// - Parameter countries: The countries the dashboard measures, already filtered.
    init(countries: [Country]) {

        let visited = countries.filter { $0.status == .visited }

        self.init(countriesVisited: visited.count,
                  countriesTotal: countries.count,
                  continentsVisited: Set(visited.compactMap(\.continent)).count,
                  continentsTotal: Set(countries.compactMap(\.continent)).count)
    }
}
