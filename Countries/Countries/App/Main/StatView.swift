//
//  StatView.swift
//  Countries
//
//  Created by Max Breuning on 15.01.26.
//

import SwiftUI
import SwiftData

/// The three dashboard numbers: countries visited, share of the world, continents visited.
///
/// - Note: Reads the countries itself rather than taking them as a parameter, so the numbers
///   stay correct wherever the view is placed.
struct StatView: View {

    // MARK: - Layout

    /// Sizes used by the percentage gauge.
    private enum Layout {
        /// Stroke width of the circular gauge.
        static let gaugeLineWidth: CGFloat = 8
        static let gaugeSize: CGFloat = 60
        /// Gap between the gauge and its caption.
        static let gaugeBottomPadding: CGFloat = 4
    }

    // MARK: - Properties

    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query(sort: \Country.iso2) private var allCountries: [Country]

    // MARK: - Body

    var body: some View {

        let source = showOnlyUNMembers ? allCountries.filter(\.isUNMember) : allCountries
        let statistics = DashboardStatistics(countries: source)

        HStack(alignment: .center, spacing: 0) {

            column {
                count(statistics.countriesVisited, of: statistics.countriesTotal)
            } caption: {
                Text("countries")
            }

            Divider()

            column {
                gauge(for: statistics)
            } caption: {
                Text("of the world")
            }

            Divider()

            column {
                count(statistics.continentsVisited, of: statistics.continentsTotal)
            } caption: {
                Text("continents")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Content

    /// One of the three columns.
    ///
    /// - Parameters:
    ///   - figure: The large part of the column — a figure or the gauge.
    ///   - caption: The caption below it.
    private func column<Figure: View, Caption: View>(
        @ViewBuilder figure: () -> Figure,
        @ViewBuilder caption: () -> Caption
    ) -> some View {

        VStack {
            figure()
            caption()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    /// An `x/y` figure.
    ///
    /// - Parameters:
    ///   - value: The reached value.
    ///   - total: The value it is measured against.
    private func count(_ value: Int, of total: Int) -> some View {

        Text(verbatim: "\(value)/\(total)")
            .font(.title3)
            .fontWeight(.semibold)
    }

    /// The circular gauge for the share of the world that has been seen.
    ///
    /// - Parameter statistics: The figures deciding what the gauge may claim.
    private func gauge(for statistics: DashboardStatistics) -> some View {

        Gauge(value: statistics.gaugeProgress) {
            shareLabel(for: statistics.worldShare)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .gaugeStyle(CircularStrokeGaugeStyle(lineWidth: Layout.gaugeLineWidth))
        .frame(width: Layout.gaugeSize, height: Layout.gaugeSize)
        .padding(.bottom, Layout.gaugeBottomPadding)
    }

    /// What the gauge prints in its centre.
    ///
    /// - Parameter share: The share the statistics allow.
    @ViewBuilder
    private func shareLabel(for share: DashboardStatistics.WorldShare) -> some View {

        switch share {
        case .unmeasurable:
            // There is nothing to divide by. A percentage here would be a claim about an
            // empty set, which is the one case where a figure would be worse than no figure.
            Text(verbatim: "—")
                .accessibilityLabel(Text("Nothing to measure yet"))
        case .percentage(let percentage):
            Text(verbatim: "\(percentage)%")
        }
    }
}

#Preview {
    StatView()
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
