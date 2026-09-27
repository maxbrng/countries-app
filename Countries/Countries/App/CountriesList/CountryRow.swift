//
//  CountryRow.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import SwiftData

/// One row of ``CountriesList``: flag, English name, ISO2 code and a status badge.
///
/// Swiping the row from the trailing edge toggles the visited or wishlist status.
struct CountryRow: View {

    // MARK: - Layout

    /// Sizes, radii and opacities used by the row.
    private enum Layout {
        /// Horizontal spacing between flag, name column and badge.
        static let contentSpacing: CGFloat = 16
        static let flagCornerRadius: CGFloat = 4
        static let flagBorderWidth: CGFloat = 1
        static let flagMaxWidth: CGFloat = 40
        static let flagMaxHeight: CGFloat = 30
        /// Padding on all edges of a status badge.
        static let badgePadding: CGFloat = 4
        /// Additional horizontal padding of a status badge.
        static let badgeExtraHorizontalPadding: CGFloat = 6
        /// Opacity of the tinted capsule behind a status badge.
        static let badgeBackgroundOpacity: Double = 0.2
    }

    // MARK: - Properties

    /// The country this row represents.
    let country: Country

    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        HStack(spacing: Layout.contentSpacing) {
            Image(country.iso2.lowercased())
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous))
                .scaledToFit()
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: Layout.flagBorderWidth)
                )
                .frame(maxWidth: Layout.flagMaxWidth, maxHeight: Layout.flagMaxHeight)

            VStack(alignment: .leading) {
                Text(country.nameEnglish)
                Text(country.iso2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            badge(for: country.status)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { toggleStatus(of: country, .visited) } label: {
                Label("Visited", systemImage: "checkmark.circle")
            }.tint(.green)

            Button { toggleStatus(of: country, .wishlist) } label: {
                Label("Wishlist", systemImage: "star")
            }.tint(.blue)
        }
    }

    // MARK: - Actions

    /// Applies `newStatus` to `country` and lets ``PreferencesService`` re-derive the
    /// recommendation preferences.
    ///
    /// - Parameters:
    ///   - country: The swiped country.
    ///   - newStatus: The status the swipe action stands for. Swiping the status the country
    ///     already has clears it again.
    private func toggleStatus(of country: Country, _ newStatus: CountryStatus) {
        try? PreferencesService.toggleStatus(newStatus, for: country, in: modelContext)
    }

    // MARK: - Helpers

    /// Capsule badge for a country that is visited or wishlisted.
    ///
    /// - Parameter status: The country's status; ``CountryStatus/none`` renders nothing.
    @ViewBuilder
    private func badge(for status: CountryStatus) -> some View {

        switch status {
        case .none:
            EmptyView()

        case .visited:
            Text("Visited")
                .padding(Layout.badgePadding)
                .padding(.horizontal, Layout.badgeExtraHorizontalPadding)
                .background(.green.opacity(Layout.badgeBackgroundOpacity))
                .clipShape(Capsule())

        case .wishlist:
            Text("Wishlist")
                .padding(Layout.badgePadding)
                .padding(.horizontal, Layout.badgeExtraHorizontalPadding)
                .background(.blue.opacity(Layout.badgeBackgroundOpacity))
                .clipShape(Capsule())
        }
    }
}
