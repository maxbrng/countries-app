//
//  MemoryPressureSignals.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import Foundation

/// When the app should hand back memory it is only caching.
///
/// The two systems disagree about what that moment is: iOS tells an app it has been
/// backgrounded and separately that memory is short, macOS has neither notification and the
/// nearest equivalent is the app losing focus. Naming the moments here keeps that difference
/// out of the code that actually owns a cache.
nonisolated enum MemoryPressureSignals {

    /// Notifications that mean "give back what you are only holding on to".
    static var releaseCaches: [Notification.Name] {
        #if canImport(UIKit)
        [UIApplication.didEnterBackgroundNotification,
         UIApplication.didReceiveMemoryWarningNotification]
        #elseif canImport(AppKit)
        // macOS has no memory-warning notification. Resigning active is the closest thing to
        // "the user is not looking at the map any more", which is the condition that matters:
        // the cache is worth about 29 MB and costs a re-parse to rebuild.
        [NSApplication.didResignActiveNotification]
        #else
        []
        #endif
    }
}
