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

        let visited = source.filter { $0.status == .visited }
        let countriesVisited = Double(visited.count)
        let totalCountries = Double(source.count)

        let totalContinents = Double(Set(source.compactMap(\.continent)).count)
        let continentsVisited = Double(Set(visited.compactMap(\.continent)).count)

        HStack(alignment: .center, spacing: 0) {

            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      caption: "countries",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      caption: "of the world",
                      graphVisualization: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: continentsVisited,
                      maxValue: totalContinents,
                      caption: "continents",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Content

    /// One of the three columns.
    ///
    /// - Parameters:
    ///   - currentValue: The reached value, for example the number of visited countries.
    ///   - maxValue: The value that stands for 100 %. A zero is treated as "nothing reached"
    ///     rather than dividing by it.
    ///   - caption: Caption below the figure, looked up in the string catalog.
    ///   - graphVisualization: `true` draws a percentage gauge instead of an `x/y` figure.
    @ViewBuilder
    private func statistic(currentValue: Double,
                           maxValue: Double,
                           caption: LocalizedStringKey,
                           graphVisualization: Bool) -> some View {

        VStack {

            if graphVisualization {
                gauge(currentValue: currentValue, maxValue: maxValue)
            } else {
                Text(verbatim: "\(Int(currentValue))/\(Int(maxValue))")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Circular gauge showing `currentValue` as a percentage of `maxValue`.
    ///
    /// - Parameters:
    ///   - currentValue: The reached value.
    ///   - maxValue: The value that stands for 100 %.
    private func gauge(currentValue: Double, maxValue: Double) -> some View {

        // Guards both a zero maximum and values outside the range.
        let progress = maxValue > 0 ? max(0, min(1, currentValue / maxValue)) : 0
        let percentage = Int((progress * 100).rounded())

        return Gauge(value: progress) {
            Text(verbatim: "\(percentage)%")
                .font(.callout)
                .fontWeight(.semibold)
        }
        .gaugeStyle(CircularStrokeGaugeStyle(lineWidth: Layout.gaugeLineWidth))
        .frame(width: Layout.gaugeSize, height: Layout.gaugeSize)
        .padding(.bottom, Layout.gaugeBottomPadding)
    }
}

#Preview {
    StatView()
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
