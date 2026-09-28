//
//  PlatformDisplayLink.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import QuartzCore

/// Creates the display link that drives the map's fling.
///
/// Both platforms have `CADisplayLink`, but only iOS lets you construct one directly: on macOS
/// a link belongs to a screen, because a Mac can have several running at different refresh
/// rates. Naming that difference here keeps ``MapDecelerator`` about deceleration.
@MainActor
enum PlatformDisplayLink {

    /// Builds a display link targeting `target`.
    ///
    /// - Parameters:
    ///   - target: The object whose `selector` is called once per frame.
    ///   - selector: The method to call, taking the link as its only argument.
    /// - Returns: The link, or `nil` when there is no screen to drive it — which on macOS is a
    ///   real state (no display attached), and the caller has to finish the fling immediately
    ///   rather than wait for frames that will never arrive.
    static func make(target: Any, selector: Selector) -> CADisplayLink? {
        #if canImport(UIKit)
        CADisplayLink(target: target, selector: selector)
        #elseif canImport(AppKit)
        NSScreen.main?.displayLink(target: target, selector: selector)
        #else
        nil
        #endif
    }
}
