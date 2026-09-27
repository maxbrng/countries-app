//
//  MapStrokeMetrics.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics

/// Stroke widths of the flat map, in screen points before the camera scale.
///
/// These live outside ``FlatMapRenderer`` because the coastline width is the one number on the
/// map with a hard performance limit attached, and both the renderer and the draw-cost test
/// have to agree on it.
///
/// - Note: **Never let a width exceed ``coastlineMaximumWidth``.** Core Graphics rasterises a
///   stroke of at most one unit as a hairline and anything wider by building real outline
///   geometry. Measured over the bundled country set, 4264 rings and 144695 vertices: a stroke
///   of 1.0 costs 2.6 ms per frame, a stroke of 1.1 costs 34.3 ms — a thirteenfold jump for a
///   tenth of a point. The map draws every country twice per frame, so crossing that line
///   turns a 12 ms frame into a 90 ms one.
nonisolated enum MapStrokeMetrics {

    // MARK: - Country borders

    /// Border width of the selected country.
    static let selectedBorderWidth: CGFloat = 1.2

    /// Hairline between two neighbouring countries.
    ///
    /// Narrower than ``coastlineMinimumWidth`` on purpose. Both are stroked along the same
    /// centreline, so whatever this covers is taken out of the middle of the coastline; what
    /// stays visible of the coast is `(coastline - this) / 2` on the seaward side.
    static let interiorBorderWidth: CGFloat = 0.25

    // MARK: - Coastline

    /// Coastline width at the minimum zoom.
    ///
    /// Only the outer half of the stroke stays visible — the country's own fill covers the
    /// inner half — so the coast reads at half of whatever this returns.
    static let coastlineMinimumWidth: CGFloat = 0.85

    /// Widest the coastline may ever be drawn.
    ///
    /// One unit exactly, which is the last width Core Graphics still treats as a hairline.
    /// See the note on the type: this is a performance limit, not a taste decision.
    static let coastlineMaximumWidth: CGFloat = 1.0

    /// How strongly the coastline follows the zoom.
    ///
    /// Below 1 the line grows more slowly than the map does, so the coast stays a line at
    /// every scale instead of becoming a band around each country.
    static let coastlineZoomExponent: CGFloat = 0.35

    /// Coastline width for one zoom level.
    ///
    /// - Parameter userZoom: The user's zoom factor on top of the fit scale, `1` at the world
    ///   view. Values below `1` are treated as `1`.
    /// - Returns: A width between ``coastlineMinimumWidth`` and ``coastlineMaximumWidth``,
    ///   in screen points.
    static func coastlineWidth(forUserZoom userZoom: CGFloat) -> CGFloat {

        guard userZoom > 1 else { return coastlineMinimumWidth }

        let grown = coastlineMinimumWidth * pow(userZoom, coastlineZoomExponent)
        return min(grown, coastlineMaximumWidth)
    }
}
