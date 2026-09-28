//
//  AppLanguage.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftUI

/// The language the app presents itself in, chosen inside the app rather than in iOS Settings.
///
/// iOS offers a per-app language of its own, but reaching it means leaving the app, and the
/// switch belongs where the rest of the appearance is chosen. Selecting one here overrides the
/// locale of the whole view tree, so every `Text` looks its string up in that language
/// immediately — no relaunch, and nothing is written to `AppleLanguages`.
///
/// - Note: ``system`` is the default and keeps following the device, including a per-app
///   language the user may have set in iOS Settings. Picking anything else takes precedence
///   over that for as long as it is set.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    /// Follow the device, or whatever iOS Settings says for this app.
    case system

    /// German, whatever the device is set to.
    case german = "de"

    /// English, whatever the device is set to.
    case english = "en"

    // MARK: - Storage

    /// `@AppStorage` key this choice is persisted under.
    static let storageKey = "appLanguage"

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Presentation

    /// Row shown in the picker.
    ///
    /// - Note: The two concrete languages are named in themselves rather than in the current
    ///   interface language, so someone who has landed in a language they cannot read can
    ///   still find their way out. Only ``system`` is translated.
    var label: Text {
        switch self {
        case .system: return Text("System language")
        case .german: return Text(verbatim: "Deutsch")
        case .english: return Text(verbatim: "English")
        }
    }

    /// The locale to impose on the view tree, or `nil` to leave the environment alone.
    ///
    /// - Returns: `nil` for ``system``, so the environment keeps whatever the device resolved.
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .german, .english: return Locale(identifier: rawValue)
        }
    }
}
