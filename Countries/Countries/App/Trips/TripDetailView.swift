//
//  TripDetailView.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI
import SwiftData

/// Spacings and sizes of ``TripDetailView``.
private enum TripDetailLayout {

    /// Corner radius of a country flag.
    static let flagCornerRadius: CGFloat = 3

    /// Border width around a country flag.
    static let flagBorderWidth: CGFloat = 1

    /// Widest a country flag may be drawn.
    static let flagMaxWidth: CGFloat = 32

    /// Tallest a country flag may be drawn.
    static let flagMaxHeight: CGFloat = 22

    /// Horizontal spacing between the flag and the country name.
    static let countryRowSpacing: CGFloat = 12
}

/// One trip in full: its dates, how long it lasted, which countries it covered and its notes.
///
/// Pushed from ``TripsListView``. Editing and deleting both start here, so the list row does
/// not have to carry them; a row that opens an editor directly gives the user no way to look
/// at a trip without also being in a position to change it.
struct TripDetailView: View {

    // MARK: - Properties

    /// The trip being shown.
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Drives the editor sheet.
    @State private var isEditing = false

    /// Drives the delete confirmation.
    @State private var showsDeleteConfirmation = false

    /// Owned by ``TripsListView``, because the undo has to outlive this screen.
    @Environment(TripDeletionCoordinator.self) private var deletion

    // MARK: - Body

    var body: some View {

        List {
            overviewSection
            countriesSection

            if let notes = trip.notes, !notes.isEmpty {
                notesSection(notes)
            }

            deleteSection
        }
        .navigationTitle(TripFormatting.displayTitle(for: trip))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            TripEditorView(subject: .existing(trip))
        }
        .sheet(isPresented: $showsDeleteConfirmation) {
            TripDeletionConfirmationView(summary: TripDeletion.summary(for: trip)) {
                deleteTrip()
            }
        }
    }

    // MARK: - Sections

    /// Dates and duration. Omitted entirely when the trip carries no dates, rather than shown
    /// with a placeholder: a trip without dates is a normal trip, not an incomplete one.
    @ViewBuilder
    private var overviewSection: some View {

        if let range = TripFormatting.dateRange(for: trip) {
            Section("Overview") {

                LabeledContent("Dates") { Text(verbatim: range) }

                if let days = TripFormatting.durationInDays(for: trip) {
                    LabeledContent("Duration") {
                        Text("^[\(days) day](inflect: true)")
                    }
                }
            }
        }
    }

    /// The countries of the trip, each one linking into its own detail screen.
    private var countriesSection: some View {

        Section("Countries") {

            if sortedCountries.isEmpty {
                Text("No countries yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedCountries, id: \.iso2) { country in
                NavigationLink {
                    CountryDetailsView(country: country)
                } label: {
                    countryRow(country)
                }
            }
        }
    }

    /// Free-form notes, shown only when there are any.
    ///
    /// - Parameter notes: The stored notes, already known to be non-empty.
    private func notesSection(_ notes: String) -> some View {
        Section("Notes") {
            Text(verbatim: notes)
        }
    }

    /// The destructive action, at the end of the list where a destructive action belongs.
    private var deleteSection: some View {
        Section {
            Button("Delete Trip", role: .destructive) {
                showsDeleteConfirmation = true
            }
        }
    }

    // MARK: - Rows

    /// Flag and name of one country.
    ///
    /// - Parameter country: The country to render.
    private func countryRow(_ country: Country) -> some View {

        HStack(spacing: TripDetailLayout.countryRowSpacing) {

            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: TripDetailLayout.flagCornerRadius,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TripDetailLayout.flagCornerRadius,
                                     style: .continuous)
                        .stroke(.quaternary, lineWidth: TripDetailLayout.flagBorderWidth)
                )
                .frame(maxWidth: TripDetailLayout.flagMaxWidth,
                       maxHeight: TripDetailLayout.flagMaxHeight)

            Text(verbatim: country.nameEnglish)
        }
    }

    // MARK: - Helpers

    /// The trip's countries in alphabetical order.
    ///
    /// Sorted here because the relationship has no order of its own, so the same trip would
    /// otherwise list its countries differently on different launches.
    private var sortedCountries: [Country] {
        trip.countries.sorted { $0.nameEnglish < $1.nameEnglish }
    }

    // MARK: - Actions

    /// Deletes the trip and leaves the screen.
    ///
    /// The undo window is opened by the coordinator rather than here, because this screen is
    /// gone a moment later and the offer has to appear on the list behind it.
    ///
    /// - Note: The relationship to ``Country`` nullifies, so every country on the trip keeps
    ///   its status — see [C-05].
    private func deleteTrip() {

        deletion.delete(trip, in: modelContext)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: Trip(title: "Spring in Europe",
                                  startDate: .now,
                                  endDate: .now.addingTimeInterval(60 * 60 * 24 * 9),
                                  notes: "Trains all the way."))
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
