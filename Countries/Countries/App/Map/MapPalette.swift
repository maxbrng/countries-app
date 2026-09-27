//
//  MapPalette.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI

/// Every colour the flat map renderer draws with, in one place.
///
/// The map is the only screen that paints large areas next to each other with no text or
/// iconography to fall back on, so each colour here is documented with the contrast ratio it
/// reaches against the surface it is actually seen against. The ratios are WCAG 2.1 relative
/// luminance ratios, computed from the sRGB values the system resolves these colours to
/// (`UIColor.label`, `.systemBackground` and `.systemFill` in their light and dark variants,
/// composited at the opacity given here).
///
/// - Note: Two pairs fall below any usable threshold and are *not* fixed here, because fixing
///   them means changing what the map looks like, which is [D-02]: wishlist against neutral
///   land reaches 1.12 in light appearance, and wishlist against visited reaches 1.15 in dark
///   appearance. Colour alone therefore cannot carry the status; a non-colour channel has to.
enum MapPalette {

    // MARK: - Opacities

    /// Opacities the fills and strokes are composited at.
    ///
    /// Kept separate from the colours so the measured ratios below can name the exact value
    /// they were computed for.
    enum Opacity {

        /// Fill opacity of a visited country.
        static let visitedFill: Double = 0.55

        /// Fill opacity of a wishlisted country.
        static let wishlistFill: Double = 0.75

        /// Fill opacity of a known country without a status.
        static let neutralFill: Double = 0.22

        /// Opacity of the hairline between two neighbouring countries.
        static let interiorBorder: Double = 0.75

        /// Opacity of the label text.
        static let label: Double = 0.70
    }

    // MARK: - Surfaces

    /// The sea, and with it the background of the whole map.
    ///
    /// Everything else is measured against this.
    static let ocean = Color(uiColor: .systemBackground)

    // MARK: - Land fills

    /// Land that is not part of the current country set: Antarctica, and anything filtered out.
    ///
    /// - Note: Contrast against ``ocean`` is 1.27 in light and 1.49 in dark appearance. This is
    ///   the lowest ratio on the map and the reason Antarctica reads as a hole in the preview
    ///   rather than as a continent; the coastline stroke of [D-01] is what carries this edge.
    static let unknownLandFill = Color(uiColor: .systemFill)

    /// Land that is known but carries no status.
    ///
    /// - Note: Contrast against ``ocean`` is 1.69 in light and 1.79 in dark appearance.
    static let neutralLandFill = Color(uiColor: .label).opacity(Opacity.neutralFill)

    /// A country the user has visited.
    ///
    /// - Note: Contrast is 2.81 against ``neutralLandFill`` and 4.76 against ``ocean`` in light
    ///   appearance, 3.49 and 6.27 in dark.
    static let visitedFill = Color(uiColor: .label).opacity(Opacity.visitedFill)

    /// A country on the user's wishlist.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 1.12 in light and 3.04 in dark
    ///   appearance; against ``visitedFill`` it is 2.52 in light and 1.15 in dark. Each
    ///   appearance therefore has one pair that colour alone cannot separate — see [D-02].
    static let wishlistFill = Color.orange.opacity(Opacity.wishlistFill)

    // MARK: - Strokes

    /// Hairline between two neighbouring countries, drawn in the sea colour so that the border
    /// reads as a gap rather than as a line of its own.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 1.50 in light and 1.65 in dark
    ///   appearance. Deliberately low: this separates two fills, it does not outline the map.
    static let interiorBorder = Color(uiColor: .systemBackground).opacity(Opacity.interiorBorder)

    /// Outline of the selected country.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 12.41 in light and 11.71 in dark
    ///   appearance — the strongest mark on the map, which is what a selection should be.
    static let selectionStroke = Color(uiColor: .label)

    // MARK: - Labels

    /// Country names drawn on top of the fills.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 6.55 in light and 6.67 in dark
    ///   appearance, so the names clear the 4.5:1 required for body text in both.
    static let labelText = Color(uiColor: .label).opacity(Opacity.label)
}
