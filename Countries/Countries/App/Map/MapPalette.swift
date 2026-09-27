//
//  MapPalette.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import UIKit

/// Every colour the flat map renderer draws with, in one place.
///
/// The map is the only screen that paints large areas next to each other with no text or
/// iconography to fall back on, so each colour here is documented with the contrast ratio it
/// reaches against the surface it is actually seen against. The ratios are WCAG 2.1 relative
/// luminance ratios of the colours the system resolves these entries to, and
/// `MapPaletteContrastTests` recomputes every one of them, so the numbers cannot go stale.
///
/// - Note: The land fills are **opaque**, blended here rather than drawn translucently. The
///   renderer paints a coastline underneath every country and relies on the neighbouring
///   fills to cover it again along shared borders; a translucent fill would let that casing
///   show through as a dark double line at every inland border. The blend reproduces exactly
///   what a translucent fill over ``ocean`` used to produce, so nothing about the map's colour
///   changes.
///
/// - Note: Two pairs fall below any usable threshold and are *not* fixed here, because fixing
///   them means changing what the map looks like, which is [D-02]: wishlist against neutral
///   land reaches 1.12 in light appearance, and wishlist against visited reaches 1.15 in dark
///   appearance. Colour alone therefore cannot carry the status; a non-colour channel has to.
enum MapPalette {

    // MARK: - Opacities

    /// The opacities the land fills are blended at.
    ///
    /// Kept as named values because the blend below consumes them and because the measured
    /// ratios only mean something next to the opacity they were measured at.
    enum Opacity {

        /// Blend weight of a visited country against the sea.
        static let visitedFill: Double = 0.55

        /// Blend weight of a wishlisted country against the sea.
        static let wishlistFill: Double = 0.75

        /// Blend weight of a known country without a status.
        static let neutralFill: Double = 0.22

        /// Blend weight of the coastline against the sea.
        ///
        /// High, because only a fraction of a point of the stroke ever stays visible; a
        /// lighter line at that width disappears into its own antialiasing.
        static let coastline: Double = 0.65

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
    ///   the lowest ratio on the map, and on its own it is what made Antarctica read as a hole
    ///   in the dashboard preview rather than as a continent. The ``coastline`` underneath is
    ///   what now carries that edge.
    static let unknownLandFill = blended(.systemFill, over: .systemBackground)

    /// Land that is known but carries no status.
    ///
    /// - Note: Contrast against ``ocean`` is 1.69 in light and 1.79 in dark appearance.
    static let neutralLandFill = blended(.label,
                                         alpha: Opacity.neutralFill,
                                         over: .systemBackground)

    /// A country the user has visited.
    ///
    /// - Note: Contrast is 2.81 against ``neutralLandFill`` and 4.76 against ``ocean`` in light
    ///   appearance, 3.49 and 6.27 in dark.
    static let visitedFill = blended(.label,
                                     alpha: Opacity.visitedFill,
                                     over: .systemBackground)

    /// A country on the user's wishlist.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 1.12 in light and 3.04 in dark
    ///   appearance; against ``visitedFill`` it is 2.52 in light and 1.15 in dark. Each
    ///   appearance therefore has one pair that colour alone cannot separate — see [D-02].
    static let wishlistFill = blended(.systemOrange,
                                      alpha: Opacity.wishlistFill,
                                      over: .systemBackground)

    // MARK: - Strokes

    /// The line between land and sea, drawn underneath every country.
    ///
    /// Along a shared border it is covered again by the neighbouring country's fill, so it
    /// only stays visible where land actually meets water.
    ///
    /// - Note: Contrast against ``ocean`` is 6.98 in light and 8.60 in dark appearance, and
    ///   against ``neutralLandFill`` 4.13 and 4.80. Both sides clear the 3:1 required of a
    ///   non-text graphic, which no land fill on its own comes close to. It has to be this
    ///   dark: only a fraction of a point of the stroke survives the fills drawn over it, and
    ///   a lighter line at that width disappears into its own antialiasing — measured, not
    ///   assumed.
    static let coastline = blended(.label, alpha: Opacity.coastline, over: .systemBackground)

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

    // MARK: - Blending

    /// Composites `top` onto `bottom` once, producing an opaque colour that still follows the
    /// light and dark appearance.
    ///
    /// - Parameters:
    ///   - top: The colour being laid on, its own alpha included in the blend.
    ///   - alpha: Additional opacity applied to `top`. Defaults to `1`, for colours such as
    ///     `UIColor.systemFill` that already carry their own alpha.
    ///   - bottom: The opaque surface underneath, in practice always the sea.
    /// - Returns: An opaque colour that renders identically to `top` drawn over `bottom`.
    private static func blended(_ top: UIColor,
                                alpha: Double = 1,
                                over bottom: UIColor) -> Color {

        Color(uiColor: UIColor { traits in

            let resolvedTop = top.resolvedColor(with: traits)
            let resolvedBottom = bottom.resolvedColor(with: traits)

            var topRed: CGFloat = 0, topGreen: CGFloat = 0, topBlue: CGFloat = 0
            var topAlpha: CGFloat = 0
            var bottomRed: CGFloat = 0, bottomGreen: CGFloat = 0, bottomBlue: CGFloat = 0
            var bottomAlpha: CGFloat = 0

            resolvedTop.getRed(&topRed, green: &topGreen, blue: &topBlue, alpha: &topAlpha)
            resolvedBottom.getRed(&bottomRed, green: &bottomGreen, blue: &bottomBlue,
                                  alpha: &bottomAlpha)

            let weight = topAlpha * alpha

            func mix(_ top: CGFloat, _ bottom: CGFloat) -> CGFloat {
                top * weight + bottom * (1 - weight)
            }

            return UIColor(red: mix(topRed, bottomRed),
                           green: mix(topGreen, bottomGreen),
                           blue: mix(topBlue, bottomBlue),
                           alpha: 1)
        })
    }
}
