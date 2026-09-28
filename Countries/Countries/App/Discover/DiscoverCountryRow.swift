//
//  DiscoverCountryRow.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import SwiftData

/// One row of ``DiscoverScreen``: flag, name, its travel tags and a wishlist toggle.
///
/// - Note: The navigation link covers only the left half of the row, so the wishlist button
///   stays tappable. A row wrapped in a link as a whole swallows every control inside it.
struct DiscoverCountryRow: View {

    // MARK: - Layout

    /// Sizes, spacings and radii used by the row.
    private enum Layout {
        static let contentSpacing: CGFloat = 16
        /// Vertical spacing between the name and the tag line.
        static let textSpacing: CGFloat = 4
        static let flagCornerRadius: CGFloat = 4
        static let flagBorderWidth: CGFloat = 1
        static let flagMaxWidth: CGFloat = 40
        static let flagMaxHeight: CGFloat = 30
    }

    /// Number of travel tags named before the line is cut short.
    private static let tagLimit = 3

    // MARK: - Properties

    /// The country this row stands for.
    let country: Country

    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {

        HStack(spacing: Layout.contentSpacing) {

            NavigationLink(value: country) {
                summary
            }

            wishlistButton
        }
    }

    // MARK: - Content

    /// Flag, name and tag line: everything the navigation link covers.
    private var summary: some View {

        HStack(spacing: Layout.contentSpacing) {

            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Layout.flagCornerRadius,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: Layout.flagBorderWidth)
                )
                .frame(maxWidth: Layout.flagMaxWidth, maxHeight: Layout.flagMaxHeight)

            VStack(alignment: .leading, spacing: Layout.textSpacing) {

                Text(country.displayName)
                    .foregroundStyle(.primary)

                tagLine
            }

            Spacer()
        }
    }

    /// The first few travel tags, as plain names.
    @ViewBuilder
    private var tagLine: some View {

        let tags = country.travelTags.prefix(Self.tagLimit)

        if !tags.isEmpty {
            HStack(spacing: Layout.textSpacing) {
                ForEach(Array(tags), id: \.self) { tag in
                    Text(tag.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Adds the country to the wishlist, or takes it off again.
    private var wishlistButton: some View {

        let isWishlisted = country.status == .wishlist

        return Button {
            try? CountryStatusService.toggleStatus(.wishlist, for: country, in: modelContext)
        } label: {
            Image(systemName: isWishlisted ? "star.fill" : "star")
                .foregroundStyle(isWishlisted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isWishlisted ? "Remove from Wishlist" : "Add to Wishlist")
    }
}
