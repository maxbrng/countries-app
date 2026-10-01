//
//  OnboardingState.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftUI

/// Whether the first launch has been dealt with.
///
/// Kept in `UserDefaults` rather than in the store, for two reasons: it is one flag about the
/// app rather than about the user's data, and resetting the data has to be able to bring the
/// first launch back — see ``DataResetService`` — which a value inside the store being reset
/// could not do for itself.
nonisolated enum OnboardingState {

    /// Key of the completion flag. Shared with the `@AppStorage` that drives the flow.
    static let storageKey = "hasCompletedOnboarding"

    /// Whether the onboarding has already run to its end or been skipped.
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    /// Marks the onboarding as dealt with, so it does not run again.
    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: storageKey)
    }

    /// Brings the first launch back, for a data reset.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
