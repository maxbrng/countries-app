//
//  OnboardingStep.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// The steps of the first launch, in order.
///
/// An enum rather than an index, so a step can be inserted without every call site having to
/// agree on what "step 2" means. ``CaseIterable`` gives the flow its order and its length.
nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable {

    /// What the app is for, in one screen.
    case welcome

    /// Which countries have already been visited.
    case markVisited

    var id: Int { rawValue }

    /// The step after this one, or `nil` when this is the last.
    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// Position of this step in the flow, counting from one, for the progress indicator.
    var number: Int { rawValue + 1 }

    /// How many steps the flow has.
    static var count: Int { allCases.count }
}
