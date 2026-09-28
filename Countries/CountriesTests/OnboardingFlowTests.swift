//
//  OnboardingFlowTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import Testing
@testable import Countries

/// Covers the two promises of the first launch: that it runs once, and that it can be left.
///
/// Both are invisible after the first minute of using the app, which is exactly why they are
/// worth pinning — a flow that reappears on every launch is not something a developer running
/// a fresh install every time would ever notice.
@MainActor
struct OnboardingFlowTests {

    // MARK: - Fixture

    /// Restores whatever the flag was, so a test never changes the simulator's own state.
    ///
    /// - Parameter body: The work to run with a cleared flag.
    private func withClearedFlag(_ body: () throws -> Void) rethrows {

        let previous = UserDefaults.standard.object(forKey: OnboardingState.storageKey)
        OnboardingState.reset()

        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: OnboardingState.storageKey)
            } else {
                OnboardingState.reset()
            }
        }

        try body()
    }

    // MARK: - Running once

    @Test
    func test_hasCompleted_onAFreshInstall_isFalse() throws {

        try withClearedFlag {
            // Act & Assert
            #expect(!OnboardingState.hasCompleted)
        }
    }

    @Test
    func test_markCompleted_isWhatStopsTheFlowComingBack() throws {

        try withClearedFlag {
            // Act
            OnboardingState.markCompleted()

            // Assert
            #expect(OnboardingState.hasCompleted)
        }
    }

    @Test
    func test_reset_bringsTheFirstLaunchBack() throws {

        try withClearedFlag {
            // Arrange
            OnboardingState.markCompleted()

            // Act
            OnboardingState.reset()

            // Assert
            #expect(!OnboardingState.hasCompleted)
        }
    }

    // MARK: - The flow's shape

    @Test
    func test_steps_runFromTheFirstToTheLastWithoutAGap() {

        // Arrange
        var visited: [OnboardingStep] = []
        var current: OnboardingStep? = .welcome

        // Act
        while let step = current {
            visited.append(step)
            current = step.next
        }

        // Assert
        // Walking `next` has to reach every case; a step whose raw value skips a number would
        // end the flow early and silently.
        #expect(visited == OnboardingStep.allCases)
        #expect(visited.count == OnboardingStep.count)
    }

    @Test
    func test_stepNumbers_countFromOne() {

        // Arrange & Act
        let numbers = OnboardingStep.allCases.map(\.number)

        // Assert
        #expect(numbers == Array(1...OnboardingStep.count))
    }
}
