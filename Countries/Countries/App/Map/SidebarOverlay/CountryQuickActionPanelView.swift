//
//  CountryQuickActionPanelView.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "CountryQuickActions")

/// Content of the country sheet on the map: the two status toggles plus the entry point
/// into the full country details.
struct CountryQuickActionPanelView: View {

    // MARK: - Constants

    /// Spacing, padding and detents of the panel.
    private enum Layout {

        /// Spacing between the action row and the details button.
        static let contentSpacing: CGFloat = 12

        /// Spacing between the two action buttons.
        static let actionSpacing: CGFloat = 12

        /// Vertical padding inside an action button.
        static let actionVerticalPadding: CGFloat = 12

        /// Smallest detent of the details sheet.
        static let detailsSmallDetent: CGFloat = 0.6

        /// Medium detent of the details sheet.
        static let detailsMediumDetent: CGFloat = 0.8
    }

    // MARK: - Input

    /// The country the panel acts on.
    let country: Country

    /// Invoked when the panel should be dismissed.
    ///
    /// - Note: The close control lives in the navigation bar of the presenting
    ///   `MapViewController`, so the panel itself does not call this.
    let onClose: () -> Void

    // MARK: - State

    @Environment(\.modelContext) private var modelContext
    @State private var showDetailSheet = false

    // MARK: - Body

    var body: some View {

        VStack(spacing: Layout.contentSpacing) {

            actionButtons

            Button {
                showDetailSheet = true
            } label: {
                Label("Show Details", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .buttonStyle(.glass)
            .sheet(isPresented: $showDetailSheet) {
                CountryDetailsView(country: country)
                    .presentationDetents([.fraction(Layout.detailsSmallDetent),
                                          .fraction(Layout.detailsMediumDetent),
                                          .large])
            }
        }
        .padding()
    }

    // MARK: - Subviews

    /// The visited and wishlist toggles.
    private var actionButtons: some View {

        HStack(spacing: Layout.actionSpacing) {

            Button {
                toggle(.visited)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Visited")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Layout.actionVerticalPadding)
            }
            .buttonStyle(.glass)
            .tint(.green)

            Button {
                toggle(.wishlist)
            } label: {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Wishlist")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Layout.actionVerticalPadding)
            }
            .buttonStyle(.glass)
            .tint(.blue)
        }
    }

    // MARK: - Actions

    /// Toggles a status for ``country``, which also refreshes the derived preferences.
    ///
    /// - Parameter status: The status to set, or to clear when the country already has it.
    /// - Note: A failure leaves the country unchanged; there is no UI for it, so it is
    ///   only logged.
    private func toggle(_ status: CountryStatus) {
        do {
            try PreferencesService.toggleStatus(status, for: country, in: modelContext)
        } catch {
            logger.error("Toggling status failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
