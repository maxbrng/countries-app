//
//  TripDeletionCoordinator.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import SwiftData
import SwiftUI

/// Owns the undo window that follows a trip deletion.
///
/// It lives above both screens that can delete a trip, because the deletion and the undo do not
/// happen in the same place: deleting from ``TripDetailView`` leaves that screen immediately,
/// so the offer to undo has to appear on ``TripsListView`` behind it.
@Observable
@MainActor
final class TripDeletionCoordinator {

    // MARK: - Nested types

    /// A deletion that can still be taken back.
    struct PendingUndo: Identifiable {

        /// Identity of this particular offer, so a second deletion replaces the first banner
        /// instead of merging with it.
        let id = UUID()

        /// The trip's title at the time it was deleted, for the banner.
        let tripTitle: String

        /// Everything needed to put it back.
        let snapshot: TripSnapshot
    }

    // MARK: - Constants

    /// How long the undo stays on offer.
    ///
    /// Long enough to notice and reach, short enough that it never covers the list while the
    /// user has moved on.
    static let undoWindow: Duration = .seconds(5)

    // MARK: - State

    /// The deletion currently on offer to undo, or `nil`.
    private(set) var pendingUndo: PendingUndo?

    /// Closes the window once it runs out. Cancelled whenever the offer changes.
    private var expiry: Task<Void, Never>?

    // MARK: - Actions

    /// Deletes `trip` and opens the undo window.
    ///
    /// - Parameters:
    ///   - trip: The trip to delete.
    ///   - context: The context holding it.
    func delete(_ trip: Trip, in context: ModelContext) {

        let title = TripFormatting.displayTitle(for: trip)
        let snapshot = TripDeletion.delete(trip, in: context)

        offer(PendingUndo(tripTitle: title, snapshot: snapshot))
    }

    /// Puts the deleted trip back and closes the window.
    ///
    /// - Parameter context: The context to insert into.
    func undo(in context: ModelContext) {

        guard let pending = pendingUndo else { return }

        TripDeletion.restore(pending.snapshot, in: context)
        clear()
    }

    /// Closes the window without restoring anything.
    func dismissUndo() {
        clear()
    }

    // MARK: - Helpers

    /// Replaces the current offer and restarts the countdown.
    ///
    /// - Parameter pending: The new offer.
    private func offer(_ pending: PendingUndo) {

        expiry?.cancel()
        pendingUndo = pending

        expiry = Task { [weak self] in

            try? await Task.sleep(for: Self.undoWindow)

            guard !Task.isCancelled, let strong = self else { return }
            guard strong.pendingUndo?.id == pending.id else { return }

            strong.pendingUndo = nil
        }
    }

    /// Drops the offer and stops the countdown.
    private func clear() {

        expiry?.cancel()
        expiry = nil
        pendingUndo = nil
    }
}
