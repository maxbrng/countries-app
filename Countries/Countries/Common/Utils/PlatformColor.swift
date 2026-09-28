//
//  PlatformColor.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import CoreGraphics
import SwiftUI

#if canImport(UIKit)
/// The platform's mutable colour type, used where SwiftUI's `Color` cannot be read back.
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
/// The platform's mutable colour type, used where SwiftUI's `Color` cannot be read back.
typealias PlatformColor = NSColor
#endif

/// The parts of a colour the map's palette needs, on whichever platform it is running.
///
/// SwiftUI's `Color` cannot be taken apart — there is no way to ask it for its components, and
/// no way to build one colour by compositing another. ``MapPalette`` has to do exactly that,
/// so it goes through the platform type and comes back out as a `Color`.
///
/// - Note: The named colours below are the *semantic* ones, not fixed values. UIKit and AppKit
///   spell them differently and there is no pair that is identical, so each is chosen for the
///   role it plays here rather than for its name.
///
/// - Note: `nonisolated` on purpose. The target's default isolation is `MainActor`, but a
///   dynamic colour's provider is a `@Sendable` closure the system calls on whichever thread
///   is drawing. Leaving these on the main actor compiles on iOS — UIKit's own provider is not
///   declared `@Sendable` — and fails the moment the same code is asked to build for macOS.
nonisolated extension PlatformColor {

    // MARK: - Semantic roles

    /// The surface everything on the map is drawn onto. The ocean, in practice.
    static var mapBackground: PlatformColor {
        #if canImport(UIKit)
        .systemBackground
        #else
        .textBackgroundColor
        #endif
    }

    /// The colour of text on that surface, used as the darkest ink the map has.
    static var mapForeground: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        .labelColor
        #endif
    }

    /// A faint fill, used for land the app knows nothing about.
    static var mapNeutralFill: PlatformColor {
        #if canImport(UIKit)
        .systemFill
        #else
        .quaternaryLabelColor
        #endif
    }

    // MARK: - Dynamic colours

    /// Builds a colour that resolves differently in light and dark appearance.
    ///
    /// - Parameter resolve: Given `true` for dark appearance, returns the colour to use.
    /// - Returns: A colour the system re-resolves whenever the appearance changes.
    static func dynamic(_ resolve: @escaping @Sendable (Bool) -> PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
        UIColor { traits in resolve(traits.userInterfaceStyle == .dark) }
        #else
        NSColor(name: nil) { appearance in
            resolve(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
        #endif
    }

    /// This colour as it appears in the given appearance.
    ///
    /// - Parameter isDark: `true` for the dark appearance.
    /// - Returns: The resolved, non-dynamic colour.
    func resolved(inDarkMode isDark: Bool) -> PlatformColor {
        #if canImport(UIKit)
        resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light))
        #else
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var resolved = self
        appearance.performAsCurrentDrawingAppearance { resolved = self.usingColorSpace(.sRGB) ?? self }
        return resolved
        #endif
    }

    /// The colour's components in sRGB.
    ///
    /// - Returns: Red, green, blue and alpha, each in 0…1. A colour that cannot be converted
    ///   to sRGB — which the system colours never are — reports as opaque black rather than
    ///   throwing, because a palette entry has to produce *something* to draw.
    var sRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {

        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
        #else
        guard let converted = usingColorSpace(.sRGB) else { return (0, 0, 0, 1) }
        return (converted.redComponent, converted.greenComponent,
                converted.blueComponent, converted.alphaComponent)
        #endif
    }

    /// An opaque colour from sRGB components.
    ///
    /// - Parameters:
    ///   - red: Red channel, 0…1.
    ///   - green: Green channel, 0…1.
    ///   - blue: Blue channel, 0…1.
    /// - Returns: The colour, fully opaque.
    static func opaque(red: CGFloat, green: CGFloat, blue: CGFloat) -> PlatformColor {
        #if canImport(UIKit)
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #else
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

nonisolated extension Color {

    /// Wraps a platform colour, keeping its dynamic behaviour.
    ///
    /// - Parameter platformColor: The colour to wrap.
    init(platform platformColor: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: platformColor)
        #else
        self.init(nsColor: platformColor)
        #endif
    }
}
