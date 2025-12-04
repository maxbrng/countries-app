import SwiftUI
import Foundation
import Combine

/// ViewModel managing the selection and visited states of countries identified by ISO codes.
/// 
/// Selection rules:
/// - Tapping a visited country toggles only its selection (selected/deselected) without altering its visited state.
/// - Selecting a country sets its state to `.selected` and clears any previously selected country.
/// - Deselecting a selected country sets its state to `.none` and clears the selection.
/// - Marking a country as visited sets its state to `.visited`, clears any selection on it, and clears any other selection.
/// 
/// The visited state persists regardless of selection toggling.
@MainActor
class CountriesViewModel: ObservableObject {
    enum CountryState: Equatable {
        case none
        case selected
        case visited
    }

    @Published var states: [String: CountryState] = [:]
    @Published var selectedCountry: String?

    /// Toggles the selection state for the given ISO country code.
    /// - If the country is visited, only toggles selection without changing visited state.
    /// - If the country is currently selected, deselects it.
    /// - Otherwise, selects the country and clears any previously selected country.
    func toggleSelection(for isoCode: String) {
        switch states[isoCode] {
        case .visited:
            // Tapping a visited country toggles only its selection, but ensure only one selection overall.
            // Clear any previously selected country state.
            if let previouslySelected = selectedCountry, previouslySelected != isoCode {
                if states[previouslySelected] == .selected {
                    states[previouslySelected] = .none
                }
            }
            // Toggle selection focus for the visited country without changing its visited state.
            if selectedCountry == isoCode {
                selectedCountry = nil
            } else {
                selectedCountry = isoCode
            }
        case .selected:
            states[isoCode] = .none
            selectedCountry = nil
        default:
            // Clear previously selected state
            if let previouslySelected = selectedCountry {
                if states[previouslySelected] == .selected {
                    states[previouslySelected] = .none
                }
            }
            states[isoCode] = .selected
            selectedCountry = isoCode
        }
    }

    /// Marks the given ISO country code as visited.
    /// Clears selection on that country and any other selected countries.
    func markVisited(for isoCode: String) {
        states[isoCode] = .visited
        if selectedCountry == isoCode {
            selectedCountry = nil
        }
        // Clear any other selected countries
        for (country, state) in states where state == .selected {
            states[country] = .none
        }
    }

    /// Clears any selected country and resets its state to `.none`.
    func clearSelection() {
        if let selected = selectedCountry, states[selected] == .selected {
            states[selected] = .none
        }
        selectedCountry = nil
    }
}

