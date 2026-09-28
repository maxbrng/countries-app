//
//  SingleCountrySelection.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Adapts ``CountryMultiSelectList`` to a question that has exactly one answer.
///
/// Rather than a second list that differs only in how many checkmarks it allows, the same list
/// is given a binding that can hold at most one code: whatever was just tapped wins, and
/// tapping the current answer clears it.
///
/// - Parameter code: The single selected ISO2 code, or `nil`.
/// - Returns: A set binding the multi-selection list can drive.
@MainActor
func singleSelectionBinding(for code: Binding<String?>) -> Binding<Set<String>> {

    Binding(
        get: { code.wrappedValue.map { [$0] } ?? [] },
        set: { newValue in
            let previous = code.wrappedValue.map { Set([$0]) } ?? []
            code.wrappedValue = newValue.subtracting(previous).first
        }
    )
}
