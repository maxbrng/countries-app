//
//  TripDeletionConfirmationView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Spacings of ``TripDeletionConfirmationView``.
private enum TripDeletionConfirmationLayout {

    /// Spacing between the two lists and the buttons.
    static let sectionSpacing: CGFloat = 20

    /// Spacing between a heading and its list.
    static let headingSpacing: CGFloat = 8

    /// Spacing between two entries of a list.
    static let entrySpacing: CGFloat = 4

    /// Spacing between the bullet and its text.
    static let bulletSpacing: CGFloat = 8

    /// Width reserved for the bullet, so the entries align.
    static let bulletWidth: CGFloat = 14

    /// Spacing between the two buttons.
    static let buttonSpacing: CGFloat = 12

    /// Height of the sheet: the lists are short, and a full-height sheet for four lines would
    /// hide the list the trip is being deleted from for no reason.
    static let detents: Set<PresentationDetent> = [.medium, .large]
}

/// Asks before deleting a trip, and names both what goes and what stays.
///
/// A sheet rather than an alert because the answer is two lists, and an alert has room for one
/// paragraph. The part users get wrong is the second list: a trip and a country's visited
/// status are separate records, so deleting the trip does not un-visit anything — but nobody
/// can know that from a generic "this cannot be undone".
struct TripDeletionConfirmationView: View {

    // MARK: - Properties

    /// What the deletion would do.
    let summary: TripDeletionSummary

    /// Called when the user goes through with it.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(alignment: .leading,
                       spacing: TripDeletionConfirmationLayout.sectionSpacing) {

                    list(heading: "This is deleted", entries: deletedEntries, symbol: "minus")
                    list(heading: "This stays", entries: keptEntries, symbol: "checkmark")

                    buttons
                }
                .padding()
            }
            .navigationTitle("Delete trip?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(TripDeletionConfirmationLayout.detents)
    }

    // MARK: - Lists

    /// One labelled list.
    ///
    /// - Parameters:
    ///   - heading: The list's heading, looked up in the string catalog.
    ///   - entries: Already formatted lines.
    ///   - symbol: SF Symbol used as the bullet, so the two lists differ without colour.
    private func list(heading: LocalizedStringKey,
                      entries: [String],
                      symbol: String) -> some View {

        VStack(alignment: .leading,
               spacing: TripDeletionConfirmationLayout.headingSpacing) {

            Text(heading)
                .font(.headline)

            VStack(alignment: .leading,
                   spacing: TripDeletionConfirmationLayout.entrySpacing) {

                ForEach(entries, id: \.self) { entry in
                    HStack(alignment: .firstTextBaseline,
                           spacing: TripDeletionConfirmationLayout.bulletSpacing) {

                        Image(systemName: symbol)
                            .font(.caption)
                            .frame(width: TripDeletionConfirmationLayout.bulletWidth)

                        Text(verbatim: entry)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The buttons, destructive first because that is what the sheet was opened for.
    private var buttons: some View {

        VStack(spacing: TripDeletionConfirmationLayout.buttonSpacing) {

            Button("Delete Trip", role: .destructive) {
                onDelete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            Button("Cancel", role: .cancel) { dismiss() }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Content

    /// What the deletion takes with it.
    private var deletedEntries: [String] {

        var entries = [String(localized: "The trip “\(summary.tripTitle)”")]

        if let range = summary.dateRange {
            entries.append(String(localized: "Its dates: \(range)"))
        }
        if summary.hasNotes {
            entries.append(String(localized: "Its notes"))
        }

        return entries
    }

    /// What survives it.
    private var keptEntries: [String] {

        var entries: [String] = []

        if summary.countryNames.isEmpty {
            entries.append(String(localized: "Every country and its visited status"))
        } else {
            let names = summary.countryNames.formatted(.list(type: .and))
            entries.append(String(localized: "\(names) — the countries themselves"))
            entries.append(String(localized: "Their visited status, which is tracked separately"))
        }

        entries.append(String(localized: "Every other trip"))

        return entries
    }
}

#Preview {
    TripDeletionConfirmationView(
        summary: TripDeletionSummary(tripTitle: "Summer in Spain",
                                     dateRange: "12 Jun 2026 – 26 Jun 2026",
                                     hasNotes: true,
                                     countryNames: ["France", "Spain"]),
        onDelete: {}
    )
}
