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
        /// Gap between the content and the buttons.
        static let footerSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 24
        /// Duration of the slide between two steps.
        static let stepAnimation: Double = 0.3
        /// Room kept under the pages for the dots the page style draws there.
        static let pageIndicatorRoom: CGFloat = 40
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

                pages

                buttons
                    .padding(.horizontal, Layout.horizontalPadding)
            }
            .safeAreaPadding(.bottom)
            .toolbar { toolbar }
        }
    }

    // MARK: - Steps

    /// Every step side by side, swipeable, with the dots underneath.
    ///
    /// A paged `TabView` rather than one view swapped out behind a button: the dots and the
    /// swipe are the same control, and this is the one iOS already draws. Building them by
    /// hand would mean reimplementing the rubber-banding at the first and last page, which is
    /// what makes a hand-rolled pager feel wrong even when it looks right.
    ///
    /// - Note: `indexDisplayMode` is `.automatic`, so a flow with a single step shows no dots.
    ///   One dot states nothing and is the same noise as "Step 1 of 1".
    private var pages: some View {

        TabView(selection: $step) {
            ForEach(OnboardingStep.allCases) { onboardingStep in
                content(for: onboardingStep)
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.bottom, Layout.pageIndicatorRoom)
                    .tag(onboardingStep)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .animation(.easeInOut(duration: Layout.stepAnimation), value: step)
    }

    /// The content of one step.
    ///
    /// - Parameter onboardingStep: The step to build.
    @ViewBuilder
    private func content(for onboardingStep: OnboardingStep) -> some View {
        switch onboardingStep {
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

        withAnimation(.easeInOut(duration: Layout.stepAnimation)) {
            step = next
        }
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
