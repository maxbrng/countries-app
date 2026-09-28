//
//  VisitedWithdrawalConfirmation.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Confirms withdrawing ``CountryStatus/visited`` from a country that still belongs to trips,
/// and states what happens to those trips.
///
/// A status and a trip are two different records of the same journey, and the app keeps them
/// independent: clearing the status leaves every trip in place, and deleting a trip leaves
/// every status in place. That is the right behaviour and the wrong thing to find out by
/// accident, which is what this dialog exists for.
///
/// It is a modifier rather than a one-off, because the status can be withdrawn from three
/// places — the country list, the country detail screen and the map's quick action panel — and
/// all three have to say the same thing.
private struct VisitedWithdrawalConfirmation: ViewModifier {

    /// The country awaiting confirmation, or `nil` while no dialog is up.
    @Binding var country: Country?

    /// Called when the user goes through with it.
    let onConfirm: (Country) -> Void

    func body(content: Content) -> some View {

        content.confirmationDialog(
            "Remove visited status?",
            isPresented: Binding(get: { country != nil },
                                 set: { if !$0 { country = nil } }),
            titleVisibility: .visible,
            presenting: country
        ) { pending in

            Button("Remove Status", role: .destructive) {
                onConfirm(pending)
                country = nil
            }

            Button("Cancel", role: .cancel) { country = nil }

        } message: { pending in
            // One literal, not two joined with `+`: automatic grammar agreement and the string
            // catalog both work on the literal key, and a concatenation produces a plain
            // runtime string that ships the markup to the user verbatim.
            Text("This country still belongs to ^[\(pending.trips.count) trip](inflect: true). Trips are kept when the status is removed and are deleted separately.")
        }
    }
}

extension View {

    /// Asks before withdrawing ``CountryStatus/visited`` from a country that still has trips.
    ///
    /// The caller decides *when* to ask by writing the country into `country`; a good test for
    /// that is ``CountryStatusService/withdrawalLeavesTrips(_:for:)``.
    ///
    /// - Parameters:
    ///   - country: The country awaiting confirmation. Set to `nil` again when the dialog
    ///     closes, whichever way it closed.
    ///   - onConfirm: Performs the withdrawal. Only called when the user confirms.
    /// - Returns: The view with the dialog attached.
    func visitedWithdrawalConfirmation(for country: Binding<Country?>,
                                       onConfirm: @escaping (Country) -> Void) -> some View {
        modifier(VisitedWithdrawalConfirmation(country: country, onConfirm: onConfirm))
    }
}
