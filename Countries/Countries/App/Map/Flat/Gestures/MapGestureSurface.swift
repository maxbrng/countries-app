//
//  MapGestureSurface.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// A transparent layer that turns whatever the platform offers into ``MapGestureHandlers``.
///
/// One protocol, two implementations: touches on iOS, scroll and magnify on macOS. The map
/// itself uses ``PlatformMapGestureSurface`` and never learns which one it got.
protocol MapGestureSurface: View {

    /// Creates the surface.
    ///
    /// - Parameter handlers: What to call as the gesture progresses.
    init(handlers: MapGestureHandlers)
}

#if canImport(UIKit)
/// The gesture surface for this platform.
typealias PlatformMapGestureSurface = TouchMapGestureSurface
#elseif canImport(AppKit)
/// The gesture surface for this platform.
typealias PlatformMapGestureSurface = PointerMapGestureSurface
#endif
