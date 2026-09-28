//
//  ScaledPathCache.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import CoreGraphics

/// Caches country paths scaled from normalized world space into the drawing rectangle.
///
/// Shapes are built once in normalized space (0...1 on both axes) and have to be scaled into
/// ``FlatMapRenderer``'s `worldRect` before they can be drawn. That scaling is a full
/// `CGPath.copy(using:)` per country, and the draw pass used to do it for every country on
/// every frame - a few hundred path copies per frame during a pan, all of them producing the
/// exact same result, because `worldRect` only changes when the view is resized or rotated.
///
/// The cache lives outside the per-frame renderer struct, the same way ``LabelMetricsCache``
/// does, so the work happens once per country per layout instead of once per frame.
///
/// - Note: Entries keep a strong reference to the source path. Its address is the cache key, and
///   a released path could otherwise be replaced by a different one at the same address.
@MainActor
final class ScaledPathCache {

    // MARK: - Nested types

    /// One cached path, held together with the source it was built from.
    private struct Entry {

        /// The source path in normalized world space, retained so its address stays unique.
        let source: CGPath

        /// The source scaled into the rectangle the cache currently holds.
        let scaled: Path
    }

    // MARK: - Constants

    /// Entry count at which the cache is emptied.
    ///
    /// One full country set is about 250 entries. The limit leaves room for a second set to
    /// arrive - a projection change replaces every path without changing the rectangle - and
    /// still bounds how long paths nobody draws any more stay alive.
    private static let maximumEntryCount = 700

    // MARK: - State

    /// The rectangle every cached path is scaled into.
    private var worldRect: CGRect = .null

    /// Scaled paths by source path address.
    private var entries: [ObjectIdentifier: Entry] = [:]

    // MARK: - Lookup

    /// Returns `cgPath` scaled into `worldRect`, building it only on a cache miss.
    ///
    /// - Parameters:
    ///   - cgPath: A country's path in normalized world space.
    ///   - worldRect: The projected world rectangle the map is drawn into. A different
    ///     rectangle empties the cache, since every entry is scaled into the previous one.
    /// - Returns: The scaled path, ready to fill and stroke.
    func path(for cgPath: CGPath, in worldRect: CGRect) -> Path {

        if worldRect != self.worldRect {
            entries.removeAll(keepingCapacity: true)
            self.worldRect = worldRect
        }

        let key = ObjectIdentifier(cgPath)

        if let cached = entries[key] { return cached.scaled }

        if entries.count >= Self.maximumEntryCount {
            entries.removeAll(keepingCapacity: true)
        }

        let scaled = Self.scaled(cgPath, into: worldRect)
        entries[key] = Entry(source: cgPath, scaled: scaled)

        return scaled
    }

    // MARK: - Building

    /// Scales a normalized path into the given rectangle.
    ///
    /// - Parameters:
    ///   - cgPath: Path in normalized world space (0...1 on both axes).
    ///   - rect: Target rectangle.
    /// - Returns: The transformed path, or the untransformed one if the copy fails.
    private static func scaled(_ cgPath: CGPath, into rect: CGRect) -> Path {

        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)

        return Path(cgPath.copy(using: &transform) ?? cgPath)
    }
}
