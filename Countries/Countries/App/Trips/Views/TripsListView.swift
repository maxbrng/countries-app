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

    /// Timings of the list.
    private enum Layout {
        /// How long the undo banner takes to appear and to leave.
        static let undoBannerAnimation: Double = 0.25
    }

    /// The trip the editor sheet is open for, or `nil` while it is closed.
    ///
    /// Only ever ``TripEditorSubject/new`` from here — an existing trip is edited from
    /// ``TripDetailView`` — but the enum is what `.sheet(item:)` needs, because `nil` already
    /// means "sheet closed".
    @State private var editorSubject: TripEditorSubject?

    /// Provided by ``RootTabView`` above the navigation stack, so that ``TripDetailView``
    /// sees the same coordinator once it is pushed.
    @Environment(TripDeletionCoordinator.self) private var deletion

    /// The trip the confirmation is open for, or `nil` while it is closed.
    @State private var deletionCandidate: Trip?

    /// Drives the alert from ``deletionCandidate``, and clears it again on dismissal.
    private var isShowingDeletionConfirmation: Binding<Bool> {
        Binding(get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } })
    }

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
        .alert("Delete trip?",
               isPresented: isShowingDeletionConfirmation,
               presenting: deletionCandidate) { trip in

            Button("Delete", role: .destructive) {
                deletion.delete(trip, in: modelContext)
            }
            Button("Cancel", role: .cancel) { }

        } message: { trip in
            Text(verbatim: TripDeletion.confirmationMessage(for: trip))
        }
        .safeAreaInset(edge: .bottom) {
            if let pending = deletion.pendingUndo {
                TripUndoBanner(tripTitle: pending.tripTitle) {
                    deletion.undo(in: modelContext)
                }
            }
        }
        .animation(.easeInOut(duration: Layout.undoBannerAnimation),
                   value: deletion.pendingUndo?.id)
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

    /// Opens the confirmation for the swiped trip.
    ///
    /// The swipe does not delete on its own: what a deletion keeps is the part users get
    /// wrong, and that has to be said before the trip is gone, not after.
    ///
    /// - Parameter offsets: Row offsets handed over by the list's delete action.
    private func deleteTrips(at offsets: IndexSet) {

        let trips = sortedTrips

        guard let index = offsets.first, trips.indices.contains(index) else { return }

        deletionCandidate = trips[index]
    }
}

#Preview {
    NavigationStack {
        TripsListView()
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
