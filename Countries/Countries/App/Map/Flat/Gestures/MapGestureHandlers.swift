//
//  MapGestureHandlers.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import CoreGraphics
import Foundation

/// What the map wants to be told about a gesture, whatever produced it.
///
/// One struct rather than nine separate closures. The nine were spelled out five times over —
/// as properties, in the initializer, in `updateUIView`, in `makeCoordinator` and again at the
/// call site — and every one of those lists had to be kept in the same order by hand.
///
/// The vocabulary is deliberately about the map and not about the input device: a pan is a pan
/// whether it came from two fingers or from a scroll wheel, and the map has no business
/// knowing which.
nonisolated struct MapGestureHandlers {

    /// A finger or the pointer landed, before any movement.
    ///
    /// The map halts its inertia here, the way Apple Maps does: a pan only begins once the
    /// touch actually moves, so without this a tap on a coasting map would not stop it.
    var onTouchDown: () -> Void = {}

    /// A pan started, before the first translation is reported.
    var onPanBegan: () -> Void = {}

    /// The translation since the previous call, not since the gesture started.
    var onPanChanged: (CGSize) -> Void = { _ in }

    /// The pan ended, carrying the final velocity in points per second, which drives the fling.
    var onPanEnded: (CGPoint) -> Void = { _ in }

    /// A zoom started, before the first scale change is reported.
    var onPinchBegan: () -> Void = {}

    /// The incremental scale factor and the centre it is applied around, in view coordinates.
    var onPinchChanged: (CGFloat, CGPoint) -> Void = { _, _ in }

    /// The zoom ended.
    var onPinchEnded: () -> Void = {}

    /// A double tap or double click, in view coordinates.
    var onDoubleTap: (CGPoint) -> Void = { _ in }

    /// A single tap or click, in view coordinates. Only fires once a double has been ruled out.
    var onTap: (CGPoint) -> Void = { _ in }
}
