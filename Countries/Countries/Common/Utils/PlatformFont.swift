//
//  PlatformFont.swift
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
import Foundation

#if canImport(UIKit)
/// The platform's font type, used only to measure text outside a draw pass.
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
/// The platform's font type, used only to measure text outside a draw pass.
typealias PlatformFont = NSFont
#endif

nonisolated extension PlatformFont {

    /// The semibold system font at `size`, which is what the map draws its labels in.
    ///
    /// - Parameter size: Point size.
    static func mapLabelFont(ofSize size: CGFloat) -> PlatformFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    /// The size `text` occupies when drawn in this font.
    ///
    /// Lives here rather than at the call site because the attribute key and the measuring
    /// method come from UIKit on one platform and AppKit on the other, and this file is the
    /// one that already knows which.
    ///
    /// - Parameter text: The string, measured exactly as it will be drawn.
    func measuredSize(of text: String) -> CGSize {
        (text as NSString).size(withAttributes: [.font: self])
    }
}
