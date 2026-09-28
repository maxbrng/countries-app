//
//  MapPaletteContrastTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import Testing
import UIKit
@testable import Countries

/// Checks that the contrast ratios written into ``MapPalette``'s documentation are the ratios
/// the colours actually reach once the system has resolved them.
///
/// The map carries its meaning in fills alone, so those numbers decide whether a status is
/// visible at all. A doc comment nobody verifies drifts away from the code the first time a
/// colour or an opacity is touched; this suite is what keeps the two together.
@MainActor
struct MapPaletteContrastTests {

    // MARK: - Helpers

    /// A colour resolved to straight sRGB components.
    private struct Resolved {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// Tolerance of a ratio comparison, in ratio points.
    ///
    /// The documented values are rounded to two decimals, so anything closer than this is the
    /// rounding and not a change of colour.
    private static let tolerance = 0.01

    /// Resolves `color` for one appearance.
    ///
    /// - Parameters:
    ///   - color: The palette entry under test.
    ///   - style: Light or dark appearance.
    /// - Returns: The resolved sRGB components, alpha kept separate.
    private func resolve(_ color: Color, in style: UIUserInterfaceStyle) -> Resolved {

        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolved = UIColor(color).resolvedColor(with: traits)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return Resolved(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Composites `color` over `background`, which is what the canvas does when it draws a
    /// translucent fill onto the sea.
    private func composite(_ color: Resolved, over background: Resolved) -> Resolved {

        func blend(_ top: Double, _ bottom: Double) -> Double {
            top * color.alpha + bottom * (1 - color.alpha)
        }

        return Resolved(red: blend(color.red, background.red),
                        green: blend(color.green, background.green),
                        blue: blend(color.blue, background.blue),
                        alpha: 1)
    }

    /// WCAG 2.1 relative luminance of an opaque colour.
    private func luminance(_ color: Resolved) -> Double {

        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    /// Contrast ratio between two opaque colours, 1.0 for identical colours and 21.0 for
    /// black against white.
    private func ratio(_ first: Resolved, _ second: Resolved) -> Double {

        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Ratio between two palette entries as they appear on the map.
    ///
    /// Both are composited onto ``MapPalette/ocean`` first, because that is what the canvas
    /// does: every fill is painted onto the sea, never onto another country's fill. Comparing
    /// a fill against an already-filled neighbour would measure a stack the renderer never
    /// draws.
    ///
    /// - Parameters:
    ///   - color: The palette entry under test.
    ///   - other: The neighbouring entry it has to be told apart from.
    ///   - style: Light or dark appearance.
    private func ratio(of color: Color,
                       against other: Color,
                       in style: UIUserInterfaceStyle) -> Double {

        let ocean = resolve(MapPalette.ocean, in: style)
        return ratio(composite(resolve(color, in: style), over: ocean),
                     composite(resolve(other, in: style), over: ocean))
    }

    /// Ratio of a colour that is painted *onto* another fill, rather than next to it.
    ///
    /// Label text and the hairline between two countries are drawn over a country that has
    /// already been filled, so their background is that fill and not the sea.
    ///
    /// - Parameters:
    ///   - color: The colour drawn on top.
    ///   - fill: The country fill underneath, itself composited onto the sea.
    ///   - style: Light or dark appearance.
    private func ratio(of color: Color,
                       onTopOf fill: Color,
                       in style: UIUserInterfaceStyle) -> Double {

        let ocean = resolve(MapPalette.ocean, in: style)
        let base = composite(resolve(fill, in: style), over: ocean)
        return ratio(composite(resolve(color, in: style), over: base), base)
    }

    // MARK: - Land against the sea

    @Test func test_unknownLandFill_againstOcean_isTheWeakestEdgeOnTheMap() {

        // Arrange / Act
        let light = ratio(of: MapPalette.unknownLandFill, against: MapPalette.ocean, in: .light)
        let dark = ratio(of: MapPalette.unknownLandFill, against: MapPalette.ocean, in: .dark)

        // Assert
        #expect(abs(light - 1.27) < Self.tolerance)
        #expect(abs(dark - 1.49) < Self.tolerance)
    }

    @Test func test_neutralLandFill_againstOcean_matchesTheDocumentedRatio() {

        let light = ratio(of: MapPalette.neutralLandFill, against: MapPalette.ocean, in: .light)
        let dark = ratio(of: MapPalette.neutralLandFill, against: MapPalette.ocean, in: .dark)

        #expect(abs(light - 1.69) < Self.tolerance)
        #expect(abs(dark - 1.79) < Self.tolerance)
    }

    // MARK: - Status fills against each other

    @Test func test_visitedFill_againstNeutralLand_clearsThreeToOne() {

        let light = ratio(of: MapPalette.visitedFill, against: MapPalette.neutralLandFill, in: .light)
        let dark = ratio(of: MapPalette.visitedFill, against: MapPalette.neutralLandFill, in: .dark)

        #expect(abs(light - 2.81) < Self.tolerance)
        #expect(abs(dark - 3.49) < Self.tolerance)
    }

    /// Documents the two pairs colour alone cannot separate.
    ///
    /// This is not a passing grade, it is a fixed record of the defect [D-02] exists for: each
    /// appearance has one pair that collapses. If a later change lifts these above 3.0, the
    /// test fails and [D-02] can be closed with a measurement instead of an opinion.
    @Test func test_wishlistFill_hasOneCollapsedPairInEachAppearance() {

        let lightAgainstNeutral = ratio(of: MapPalette.wishlistFill,
                                        against: MapPalette.neutralLandFill, in: .light)
        let darkAgainstVisited = ratio(of: MapPalette.wishlistFill,
                                       against: MapPalette.visitedFill, in: .dark)

        #expect(abs(lightAgainstNeutral - 1.12) < Self.tolerance)
        #expect(abs(darkAgainstVisited - 1.15) < Self.tolerance)
    }

    // MARK: - Strokes and labels

    @Test func test_selectionStroke_isTheStrongestMarkOnTheMap() {

        let light = ratio(of: MapPalette.selectionStroke,
                          against: MapPalette.neutralLandFill, in: .light)
        let dark = ratio(of: MapPalette.selectionStroke,
                         against: MapPalette.neutralLandFill, in: .dark)

        #expect(abs(light - 12.41) < Self.tolerance)
        #expect(abs(dark - 11.71) < Self.tolerance)
    }

    @Test func test_interiorBorder_isDeliberatelyFaintAgainstTheFillItSeparates() {

        let light = ratio(of: MapPalette.interiorBorder,
                          onTopOf: MapPalette.neutralLandFill, in: .light)
        let dark = ratio(of: MapPalette.interiorBorder,
                         onTopOf: MapPalette.neutralLandFill, in: .dark)

        #expect(abs(light - 1.50) < Self.tolerance)
        #expect(abs(dark - 1.65) < Self.tolerance)
    }

    @Test func test_labelText_againstNeutralLand_clearsBodyTextContrast() {

        let light = ratio(of: MapPalette.labelText,
                          onTopOf: MapPalette.neutralLandFill, in: .light)
        let dark = ratio(of: MapPalette.labelText,
                         onTopOf: MapPalette.neutralLandFill, in: .dark)

        #expect(light > 4.5)
        #expect(dark > 4.5)
        #expect(abs(light - 6.55) < Self.tolerance)
        #expect(abs(dark - 6.67) < Self.tolerance)
    }
}
