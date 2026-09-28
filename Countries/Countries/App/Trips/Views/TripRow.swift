//
//  TripRow.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI

/// Sizes, spacings and radii of ``TripRow``.
private enum TripRowLayout {

    /// Vertical spacing between title, dates and the flag strip.
    static let contentSpacing: CGFloat = 6

    /// Horizontal spacing between two flags of the strip.
    static let flagSpacing: CGFloat = 4

    static let flagCornerRadius: CGFloat = 2
    static let flagBorderWidth: CGFloat = 1
    static let flagMaxWidth: CGFloat = 22
    static let flagMaxHeight: CGFloat = 15

    /// Number of flags shown before the row falls back to a plain country count.
    static let flagLimit = 6
}

/// One row of ``TripsListView``: title, date range and the flags of the countries on the trip.
struct TripRow: View {

    // MARK: - Properties

    /// The trip this row represents.
    let trip: Trip

    // MARK: - Body

    var body: some View {

        VStack(alignment: .leading, spacing: TripRowLayout.contentSpacing) {

            Text(TripFormatting.displayTitle(for: trip))
                .font(.headline)
                .foregroundStyle(.primary)

            if let range = TripFormatting.dateRange(for: trip) {
                Text(range)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            flagStrip
        }
        .padding(.vertical, TripRowLayout.contentSpacing)
    }

    // MARK: - Flags

    /// The first few country flags, plus a counter for the rest.
    @ViewBuilder
    private var flagStrip: some View {

        let countries = trip.countries.sorted { $0.nameEnglish < $1.nameEnglish }
        let remainingCount = max(0, countries.count - TripRowLayout.flagLimit)

        // A ViewBuilder cannot return early, so this branch stays an if/else.
        if countries.isEmpty {
            Text("No countries yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: TripRowLayout.flagSpacing) {

                ForEach(countries.prefix(TripRowLayout.flagLimit), id: \.iso2) { country in
                    Image(country.iso2.lowercased())
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: TripRowLayout.flagCornerRadius,
                                                    style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: TripRowLayout.flagCornerRadius,
                                             style: .continuous)
                                .stroke(.quaternary, lineWidth: TripRowLayout.flagBorderWidth)
                        )
                        .frame(maxWidth: TripRowLayout.flagMaxWidth,
                               maxHeight: TripRowLayout.flagMaxHeight)
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(countries.count) countries")
        }
    }
}
