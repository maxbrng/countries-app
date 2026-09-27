//
//  LabelMetricsCache.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import UIKit
import CoreGraphics

/// Caches measured label sizes across frames.
///
/// `drawLabels` used to call `GraphicsContext.resolve` and `measure` for every
/// country on every frame, which during a pan or a fling is a few hundred text
/// layouts per frame. Measuring through UIKit instead lets the result be cached
/// outside the draw closure, so only the labels that actually survive the fit and
/// collision checks get resolved and drawn.
@MainActor
final class LabelMetricsCache {

    // MARK: - Nested types

    /// Cache key: the label string paired with its font size rounded to a whole point.
    private struct Key: Hashable {
        let text: String
        let fontSize: Int
    }

    // MARK: - State

    /// Measured sizes by key. The label vocabulary is bounded by the number of
    /// countries times the handful of font sizes the zoom range produces, so the
    /// cache is allowed to grow for the lifetime of the map.
    private var sizes: [Key: CGSize] = [:]

    // MARK: - Measuring

    /// Returns the drawn size of a label, measuring through UIKit only on a cache miss.
    /// - Parameters:
    ///   - text: The label string, measured exactly as it will be drawn.
    ///   - fontSize: Point size of the semibold system font used for the label.
    ///     Rounded to a whole point so the cache actually hits;
    ///     the continuous zoom-derived size would miss on every frame.
    /// - Returns: The size the text occupies when drawn with that font.
    func size(for text: String, fontSize: CGFloat) -> CGSize {

        let key = Key(text: text, fontSize: Int(fontSize.rounded()))

        if let cached = sizes[key] { return cached }

        let font = UIFont.systemFont(ofSize: CGFloat(key.fontSize), weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: font])

        sizes[key] = size
        return size
    }
}
