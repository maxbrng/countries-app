//
//  LoadStateOverlay.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// The one way this app reports that something is loading or has failed.
///
/// Both messages are required parameters, which is what keeps a bare spinner out of the app:
/// there is no way to show this view without saying what is being loaded, and no way to show a
/// failure without offering the retry.
///
/// - Note: Renders nothing for ``LoadState/idle`` and ``LoadState/ready``, so it can sit in an
///   `overlay` unconditionally.
struct LoadStateOverlay: View {

    // MARK: - Layout

    /// Sizes of the two boxes.
    private enum Layout {
        /// Gap between the spinner and its caption.
        static let loadingSpacing: CGFloat = 8
        /// Padding inside both boxes.
        static let padding: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        /// Keeps the failure box off the edges on a narrow screen.
        static let failureHorizontalPadding: CGFloat = 24
        /// Gap between the failure lines and the retry button.
        static let failureSpacing: CGFloat = 12
    }

    // MARK: - Properties

    /// The state to report.
    let state: LoadState

    /// What is being loaded, in one clause — "Building the map", not "Loading".
    let loadingMessage: LocalizedStringKey

    /// What failed, in one sentence the reader can act on.
    let failureMessage: LocalizedStringKey

    /// Runs the load again.
    let onRetry: () -> Void

    // MARK: - Body

    var body: some View {

        switch state {
        case .idle, .ready:
            EmptyView()
        case .loading:
            loading
        case .failed:
            failure
        }
    }

    // MARK: - States

    /// The spinner, never without its caption.
    private var loading: some View {

        VStack(spacing: Layout.loadingSpacing) {
            ProgressView()
            Text(loadingMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(Layout.padding)
        .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// The failure, never without its retry.
    private var failure: some View {

        VStack(spacing: Layout.failureSpacing) {

            Label("Could not be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text(failureMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(Layout.padding)
        .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))
        .padding(.horizontal, Layout.failureHorizontalPadding)
    }
}

#Preview("Loading") {
    LoadStateOverlay(state: .loading,
                     loadingMessage: "Building the map…",
                     failureMessage: "The map data could not be read.",
                     onRetry: {})
}

#Preview("Failed") {
    LoadStateOverlay(state: .failed,
                     loadingMessage: "Building the map…",
                     failureMessage: "The map data could not be read.",
                     onRetry: {})
}
