//
//  MapPalette.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI

/// Every colour the map draws with, in one place.
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
    /// - Note: `nonisolated` because ``interiorBorder`` reads these from the `@Sendable`
    ///   closure of a dynamic colour, which the system calls on whichever thread is drawing.
    nonisolated enum Opacity {

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

        /// Opacity of the hairline between two neighbouring countries, in light appearance.
        static let interiorBorderLight: Double = 0.75

        /// The same hairline in dark appearance.
        ///
        /// Lower than its light counterpart, and not for taste. The border is drawn in the sea
        /// colour so that it reads as a gap; in dark appearance the sea is pure black, so at
        /// 0.75 the gap lands on #0E0E0E against a land fill of #383838. That is a perceptual
        /// step of 19.6 L*, against the 14.9 L* the same opacity produces in light appearance -
        /// the border stops reading as a gap and starts reading as ink.
        ///
        /// 0.56 is the opacity at which the dark step matches the light one: 14.97 L* against
        /// 14.93. WCAG contrast barely registers the change - it moves from 1.65 to 1.51, while
        /// the border stops looking like ink - which is why the ratios alone said the two
        /// appearances were already equivalent when they plainly were not.
        static let interiorBorderDark: Double = 0.56

        /// Opacity of the label text.
        static let label: Double = 0.70
    }

    // MARK: - Surfaces

    /// The sea, and with it the background of the whole map.
    ///
    /// Everything else is measured against this.
    static let ocean = Color(platform: .mapBackground)

    // MARK: - Land fills

    /// Land that is not part of the current country set: Antarctica, and anything filtered out.
    ///
    /// - Note: Contrast against ``ocean`` is 1.27 in light and 1.49 in dark appearance. This is
    ///   the lowest ratio on the map, and on its own it is what made Antarctica read as a hole
    ///   in the dashboard preview rather than as a continent. The ``coastline`` underneath is
    ///   what now carries that edge.
    static let unknownLandFill = blended(.mapNeutralFill, over: .mapBackground)

    /// Land that is known but carries no status.
    ///
    /// - Note: Contrast against ``ocean`` is 1.69 in light and 1.79 in dark appearance.
    static let neutralLandFill = blended(.mapForeground,
                                         alpha: Opacity.neutralFill,
                                         over: .mapBackground)

    /// A country the user has visited.
    ///
    /// - Note: Contrast is 2.81 against ``neutralLandFill`` and 4.76 against ``ocean`` in light
    ///   appearance, 3.49 and 6.27 in dark.
    static let visitedFill = blended(.mapForeground,
                                     alpha: Opacity.visitedFill,
                                     over: .mapBackground)

    /// A country on the user's wishlist.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 1.12 in light and 3.04 in dark
    ///   appearance; against ``visitedFill`` it is 2.52 in light and 1.15 in dark. Each
    ///   appearance therefore has one pair that colour alone cannot separate — see [D-02].
    static let wishlistFill = blended(.systemOrange,
                                      alpha: Opacity.wishlistFill,
                                      over: .mapBackground)

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
    static let coastline = blended(.mapForeground, alpha: Opacity.coastline, over: .mapBackground)

    /// Lines of the status hatch, drawn inside a marked country.
    ///
    /// The sea colour, so the hatch reads as the fill being cut away rather than as a second
    /// colour laid over it — which is the point: it has to work when the two fills it
    /// separates are indistinguishable.
    ///
    /// - Note: Contrast against ``visitedFill`` is 4.76 in light and 6.27 in dark appearance,
    ///   against ``wishlistFill`` 1.89 and 5.46. The weak one is wishlist in light appearance,
    ///   which is also the fill whose colour collapses there, so the hatch carries it on
    ///   texture: the lines are 0.9 pt of sea colour inside an otherwise solid shape.
    static let statusHatch = ocean

    /// Hairline between two neighbouring countries, drawn in the sea colour so that the border
    /// reads as a gap rather than as a line of its own.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 1.50 in light and 1.51 in dark
    ///   appearance. Deliberately low: this separates two fills, it does not outline the map.
    ///   The two appearances carry different opacities so that they produce the same
    ///   *perceptual* step - see ``Opacity/interiorBorderDark`` for why the contrast ratio is
    ///   the wrong measure here.
    static let interiorBorder = Color(platform: .dynamic { isDark in

        let opacity = isDark ? Opacity.interiorBorderDark : Opacity.interiorBorderLight

        return PlatformColor.mapBackground
            .resolved(inDarkMode: isDark)
            .withAlphaComponent(opacity)
    })

    /// The dot marking the country the user lives in.
    ///
    /// The system accent colour, which is what a map uses for "you are here" and the one
    /// colour on this screen that carries no status meaning: visited and wishlist are drawn
    /// from the label colour and orange, so the accent cannot be mistaken for either.
    ///
    /// - Note: Contrast against ``visitedFill`` is the pair to watch, since the home country
    ///   is always visited. The white ring drawn around the dot is what actually separates it
    ///   from the fill, which is why the dot itself does not have to.
    static let homeMarker = Color.accentColor

    /// Outline of the selected country.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 12.41 in light and 11.71 in dark
    ///   appearance — the strongest mark on the map, which is what a selection should be.
    static let selectionStroke = Color(platform: .mapForeground)

    // MARK: - Labels

    /// Country names drawn on top of the fills.
    ///
    /// - Note: Contrast against ``neutralLandFill`` is 6.55 in light and 6.67 in dark
    ///   appearance, so the names clear the 4.5:1 required for body text in both.
    static let labelText = Color(platform: .mapForeground).opacity(Opacity.label)

    // MARK: - Globe

    /// Colours of the overlays drawn on top of MapKit's imagery.
    ///
    /// The globe is a different problem from the flat map: there is no palette underneath, only
    /// photography, and the same line crosses bright desert and dark ocean within one country.
    /// Nothing measured against a known background applies here, so the outline is built as a
    /// casing instead — a dark line underneath a light one, which is how a line is made legible
    /// over an image it cannot predict.
    enum Globe {

        /// The light half of the outline, drawn on top.
        static let outline = Color.white

        /// The dark half, drawn underneath and slightly wider, so that the light line always
        /// has something dark behind it no matter what the imagery does.
        static let outlineCasing = Color.black

        /// A country the user has visited.
        static let visitedFill = Color.blue

        /// A country on the user's wishlist.
        static let wishlistFill = Color.orange

        /// A country that carries no status but is selected or otherwise overlaid.
        static let neutralFill = Color.white
    }

    // MARK: - Blending

    /// Composites `top` onto `bottom` once, producing an opaque colour that still follows the
    /// light and dark appearance.
    ///
    /// - Parameters:
    ///   - top: The colour being laid on, its own alpha included in the blend.
    ///   - alpha: Additional opacity applied to `top`. Defaults to `1`, for colours such as
    ///     ``PlatformColor/mapNeutralFill`` that already carry their own alpha.
    ///   - bottom: The opaque surface underneath, in practice always the sea.
    /// - Returns: An opaque colour that renders identically to `top` drawn over `bottom`.
    private static func blended(_ top: PlatformColor,
                                alpha: Double = 1,
                                over bottom: PlatformColor) -> Color {

        Color(platform: .dynamic { isDark in

            let topComponents = top.resolved(inDarkMode: isDark).sRGBComponents
            let bottomComponents = bottom.resolved(inDarkMode: isDark).sRGBComponents

            let weight = topComponents.alpha * alpha

            func mix(_ top: CGFloat, _ bottom: CGFloat) -> CGFloat {
                top * weight + bottom * (1 - weight)
            }

            return .opaque(red: mix(topComponents.red, bottomComponents.red),
                           green: mix(topComponents.green, bottomComponents.green),
                           blue: mix(topComponents.blue, bottomComponents.blue))
        })
    }
}
