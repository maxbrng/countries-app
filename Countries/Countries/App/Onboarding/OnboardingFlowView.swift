//
//  OnboardingFlowView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// The first launch, once.
///
/// Presented over the app rather than instead of it, so the flow can be left at any point and
/// the app underneath is already built and seeded. Nothing here asks for an account, a sign-in
/// or a system permission: the first thing the user does in this app is useful, not
/// administrative.
struct OnboardingFlowView: View {

    // MARK: - Layout

    /// Spacings of the flow's frame around each step.
    private enum Layout {
        /// Gap between the progress line and the step's own content.
        static let headerSpacing: CGFloat = 8
        /// Gap between the content and the buttons.
        static let footerSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 24
        /// Duration of the slide between two steps.
        static let stepAnimation: Double = 0.3
    }

    // MARK: - Properties

    /// Survives a restart, which is what makes this run exactly once.
    @AppStorage(OnboardingState.storageKey) private var hasCompletedOnboarding = false

    /// The step on screen.
    @State private var step: OnboardingStep = .welcome

    // MARK: - Body

    var body: some View {

        NavigationStack {

            VStack(spacing: Layout.footerSpacing) {

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)))

                buttons
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .safeAreaPadding(.bottom)
            .animation(.easeInOut(duration: Layout.stepAnimation), value: step)
            .toolbar { toolbar }
        }
    }

    // MARK: - Steps

    /// The step currently on screen.
    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView()
        }
    }

    // MARK: - Chrome

    /// Where the user is, and the way out.
    ///
    /// Every step carries its own Skip, because a flow that can only be left at the end is not
    /// skippable — it is a form with a longer road to the exit.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {

        ToolbarItem(placement: .principal) {
            // A flow with one step has no position worth reporting; "Step 1 of 1" is noise.
            if OnboardingStep.count > 1 {
                Text("Step \(step.number) of \(OnboardingStep.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            // Only where it skips something. On the last step the primary button already ends
            // the flow, and two controls doing the same thing read as a choice that is not one.
            if step.next != nil {
                Button("Skip") { finish() }
            }
        }
    }

    /// Moves on, or ends the flow on the last step.
    private var buttons: some View {

        Button(step.next == nil ? "Start" : "Continue") { advance() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Goes to the next step, or finishes.
    private func advance() {

        guard let next = step.next else {
            finish()
            return
        }

        step = next
    }

    /// Closes the flow for good.
    ///
    /// Writing the flag is what dismisses the cover: the flag is the single fact, and a second
    /// piece of state saying "the sheet is closed" could disagree with it.
    private func finish() {
        hasCompletedOnboarding = true
    }
}

#Preview {
    OnboardingFlowView()
}
