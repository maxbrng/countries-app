//
//  MapStrokeMetrics.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics

/// Line widths of the flat map.
///
/// These live outside ``FlatMapRenderer`` because they are the numbers that decide whether a
/// frame stays cheap: Core Graphics rasterises a stroke as a hairline only up to one unit, and
/// a width that crosses that line turns a 12 ms frame into a 90 ms one.
nonisolated enum MapStrokeMetrics {

    // MARK: - Country borders

    /// Border width of the selected country.
    static let selectedBorderWidth: CGFloat = 1.2

    /// Hairline between two neighbouring countries.
    ///
    /// Drawn in the sea colour, so the border reads as a gap between two fills rather than as
    /// a line of its own.
    static let interiorBorderWidth: CGFloat = 0.25
}
