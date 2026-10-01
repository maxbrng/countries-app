//
//  TripsListView.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import SwiftData

/// List of the user's trips, newest first.
///
/// A row pushes ``TripDetailView``; editing and deleting start there. Creating a trip happens
/// in ``TripEditorView``, presented as a sheet from here, so an abandoned new trip never
/// reaches the store.
struct TripsListView: View {

    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext

    @Query private var allTrips: [Trip]

    /// The trip the editor sheet is open for, or `nil` while it is closed.
    ///
    /// Only ever ``TripEditorSubject/new`` from here — an existing trip is edited from
    /// ``TripDetailView`` — but the enum is what `.sheet(item:)` needs, because `nil` already
    /// means "sheet closed".
    @State private var editorSubject: TripEditorSubject?

    // MARK: - Body

    var body: some View {

        Group {
            if allTrips.isEmpty {
                emptyState
            } else {
                tripList
            }
        }
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorSubject = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add trip")
            }
        }
        .sheet(item: $editorSubject) { subject in
            TripEditorView(subject: subject)
        }
    }

    // MARK: - Content

    /// Trips sorted newest first.
    ///
    /// Sorted here rather than in the `@Query` so that trips without a start date land at the
    /// end instead of wherever the store puts `nil`.
    private var sortedTrips: [Trip] {
        TripFormatting.sortedNewestFirst(allTrips)
    }

    /// The populated list, with swipe-to-delete on each row.
    private var tripList: some View {
        List {
            ForEach(sortedTrips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip)
                } label: {
                    TripRow(trip: trip)
                }
            }
            .onDelete(perform: deleteTrips)
        }
    }

    /// Shown while no trip exists. Carries exactly one action, so there is no doubt about the
    /// next step.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No trips yet", systemImage: "suitcase.rolling")
        } description: {
            Text("Group the countries of a journey into a trip.")
        } actions: {
            Button("Add your first trip") {
                editorSubject = .new
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    /// Deletes the trips at `offsets` of ``sortedTrips``.
    ///
    /// - Parameter offsets: Row offsets handed over by the list's delete action.
    /// - Note: The relationship to ``Country`` nullifies, so the countries themselves and their
    ///   statuses survive the deletion.
    private func deleteTrips(at offsets: IndexSet) {

        let trips = sortedTrips
        for index in offsets where trips.indices.contains(index) {
            modelContext.delete(trips[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        TripsListView()
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
