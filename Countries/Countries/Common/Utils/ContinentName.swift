//
//  ContinentName.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// Turns the two-letter continent code stored on ``Country`` into a name a reader recognises.
///
/// One place for it, because the same code is shown as a section heading in the country list
/// and as a field on the detail screen, and the two must not disagree.
nonisolated enum ContinentName {

    /// Code used when a country carries no continent.
    static let unknownCode = "??"

    /// Localized name for a continent code.
    ///
    /// - Parameter code: Two-letter continent code as stored on ``Country``.
    /// - Returns: The continent's name in the app's language, or the code itself when it is
    ///   not one this app knows — showing the raw code says "unrecognised data" more honestly
    ///   than inventing a name for it.
    static func name(for code: String) -> String {

        switch code {
        case "AF": String(localized: "Africa")
        case "AN": String(localized: "Antarctica")
        case "AS": String(localized: "Asia")
        case "EU": String(localized: "Europe")
        case "NA": String(localized: "North America")
        case "OC": String(localized: "Oceania")
        case "SA": String(localized: "South America")
        case unknownCode: String(localized: "Unknown")
        default: code
        }
    }
}
