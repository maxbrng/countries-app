//
//  StatusHatching.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import SwiftUI

/// The non-colour channel that tells the tracking states apart on the map.
///
/// Four fills can never all clear 3:1 against each other — the fourth step would need a
/// relative luminance above 1.0, and white is 1.0 — and the measured palette shows where that
/// bites: wishlist sits at 1.12 against neutral land in light appearance and at 1.15 against
/// visited in dark. Each appearance has one pair that colour alone cannot separate, so the
/// status has to be carried by a second channel as well.
///
/// The channel is a hatch, drawn by the renderer into the same canvas as the fills rather than
/// by a layer on top: an overlay would need its own geometry, its own camera and its own
/// caching, and would drift out of step with the map on every pan.
///
/// - Note: Visited and wishlist hatch in opposite directions, so the three states a country
///   can be in — unmarked, visited, wishlisted — are told apart by texture alone, with the
///   screen in greyscale or the colours indistinguishable.
nonisolated enum StatusHatching {

    // MARK: - Direction

    /// Which way the hatch lines run.
    enum Direction {

        /// Bottom-left to top-right. Visited.
        case rising

        /// Top-left to bottom-right. Wishlisted.
        case falling

        /// Horizontal offset a line gains over the full height of the area it covers.
        ///
        /// - Parameter height: Height of the area being hatched.
        /// - Returns: The run to add to a line's start x to reach its end x.
        fileprivate func run(over height: CGFloat) -> CGFloat {
            switch self {
            case .rising: -height
            case .falling: height
            }
        }
    }

    // MARK: - Constants

    /// Perpendicular distance between two hatch lines, in screen points.
    ///
    /// Wide enough that the fill still reads as a colour rather than as a texture, narrow
    /// enough that a country the size of Luxembourg still shows two lines at a useful zoom.
    static let spacing: CGFloat = 7

    /// Width of a hatch line, in screen points.
    ///
    /// - Note: At or below one unit on purpose. Core Graphics rasterises a stroke of at most
    ///   one unit as a hairline and anything wider by building outline geometry, which over
    ///   this many lines is the difference between a few milliseconds and tens of them. The
    ///   same limit is documented on ``MapStrokeMetrics``.
    static let lineWidth: CGFloat = 0.9

    /// Highest number of lines drawn for one country.
    ///
    /// A hard stop rather than a target: the hatch is clipped to what is on screen, but a
    /// degenerate camera should never be able to ask for an unbounded number of lines.
    static let maximumLineCount = 400

    // MARK: - Geometry

    /// Builds the hatch lines covering `area`.
    ///
    /// The lines are generated directly at their angle instead of drawing axis-aligned lines
    /// into a rotated context, because the canvas is already carrying the camera transform and
    /// a second rotation on top of it would also rotate the clip.
    ///
    /// - Parameters:
    ///   - area: The rectangle to cover, in the coordinate space being drawn in. Usually a
    ///     country's bounding box intersected with what is visible.
    ///   - direction: Which way the lines run.
    ///   - spacing: Perpendicular distance between two lines, in the same space as `area`.
    /// - Returns: A path of parallel line segments, empty when `area` is empty.
    static func path(covering area: CGRect,
                     direction: Direction,
                     spacing: CGFloat) -> Path {

        var path = Path()

        guard !area.isEmpty, spacing > 0 else { return path }

        let run = direction.run(over: area.height)

        // Measured perpendicular to the lines, a 45 degree step of `spacing` along x puts the
        // lines `spacing / sqrt(2)` apart, so the step is scaled back up to keep the spacing
        // the caller asked for.
        let step = spacing * 2.squareRoot()

        // The lines lean, so the range of start positions has to be widened by the lean to
        // cover the whole rectangle at both ends.
        let start = run < 0 ? area.minX : area.minX - run
        let end = run < 0 ? area.maxX - run : area.maxX

        var drawn = 0
        var x = start

        while x <= end, drawn < maximumLineCount {
            path.move(to: CGPoint(x: x, y: area.minY))
            path.addLine(to: CGPoint(x: x + run, y: area.maxY))
            x += step
            drawn += 1
        }

        return path
    }
}
