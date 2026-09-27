//
//  MapScreenModel.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import Observation
import SwiftUI

/// Which of the two map renderers the map screen shows.
enum MapAppearance: Hashable, CaseIterable {
    /// The flat, projected map drawn with `Canvas` and `CGPath`.
    case twoD
    /// The three-dimensional globe.
    case threeD
}

/// Which detent the base (search) sheet currently rests on.
/// Mirrors the UIKit detents without leaking UIKit into the SwiftUI layer.
enum BaseSheetDetent: Hashable {
    /// Collapsed to the height of the search bar.
    case small
    /// Half height. Portrait only; landscape has no meaningful half state.
    case medium
    /// Full height.
    case large
}

/// What is stacked on top of the base sheet. Exactly one thing can be - modelling
/// it as an enum instead of two independent booleans removes the state where both
/// claim to be up at once.
enum MapSheetRoute: Equatable {
    /// Nothing stacked; only the base search sheet is up.
    case none
    /// The quick-action sheet for a selected country.
    case country(Country)
    /// The map appearance sheet.
    case appearance

    /// The selected ``Country``, or `nil` for any other route.
    var country: Country? {
        if case .country(let country) = self { return country }
        return nil
    }

    /// Whether this route is the appearance sheet.
    var isAppearance: Bool { self == .appearance }
}

/// Shared state of the map screen.
///
/// The `UIHostingController` root view is built once against this model, so
/// changing appearance or selection never replaces the SwiftUI tree - that
/// teardown was what left the map blank and the sheet stack wedged.
///
/// The state is split in two halves that must not be confused:
///
/// * **Intent** - `route`, `isSearchFieldFocused`, `appearance`, `filter`.
///   Written by whoever the user interacted with (a map tap, the search field,
///   the appearance picker). `MapViewController` observes these and translates
///   them into presentations and detents.
/// * **Presentation** - `baseDetent`, `presentedRoute`, `hidesBaseSheetContent`.
///   Owned by `MapViewController`, `private(set)` here and only writable through
///   `apply(...)`. Views read them, never set them.
///
/// Keeping the halves apart is what stops the two layers from briefly claiming
/// different things while a sheet animates.
@Observable
@MainActor
final class MapScreenModel {

    // MARK: - Intent

    /// Which renderer is shown. Defaults to ``MapAppearance/twoD``.
    var appearance: MapAppearance = .twoD

    /// Which countries the map highlights. Defaults to `.all`.
    var filter: CountryStatusFilter = .all

    /// What the user wants stacked on the base sheet.
    var route: MapSheetRoute = .none

    /// Set by the search field. The controller raises a collapsed base sheet so
    /// results have room, and lowers it again when focus is lost.
    var isSearchFieldFocused: Bool = false

    /// Convenience over `route` so map views can keep binding a plain optional.
    var selectedCountry: Country? {
        get { route.country }
        set {
            if let newValue {
                route = .country(newValue)
            } else if route.country != nil {
                route = .none
            }
        }
    }

    /// Convenience over `route` for the appearance button / panel.
    var showAppearancePanel: Bool {
        get { route.isAppearance }
        set {
            if newValue {
                route = .appearance
            } else if route.isAppearance {
                route = .none
            }
        }
    }

    // MARK: - Presentation (written by MapViewController only)

    /// The detent the base sheet actually rests on.
    private(set) var baseDetent: BaseSheetDetent = .small

    /// What is actually on screen. Lags `route` by one presentation animation,
    /// which is precisely why it is a separate value.
    private(set) var presentedRoute: MapSheetRoute = .none

    /// Whether the base sheet is currently too short to show anything below its
    /// search bar. Derived from the sheet's real height, not from detent
    /// bookkeeping, so it is correct mid-drag as well as mid-animation.
    private(set) var hidesBaseSheetContent: Bool = true

    /// Whether a country sheet is on screen right now.
    var isCountrySheetPresented: Bool { presentedRoute.country != nil }

    /// Whether the appearance sheet is on screen right now.
    var isAppearanceSheetPresented: Bool { presentedRoute.isAppearance }

    /// Whether anything at all is stacked on the base sheet right now.
    var isAnySecondarySheetPresented: Bool { presentedRoute != .none }

    // MARK: - Presentation updates

    /// Publishes the presentation state ``MapViewController`` observed on UIKit.
    ///
    /// - Parameters:
    ///   - baseDetent: The detent the base sheet actually rests on.
    ///   - presentedRoute: What is actually on screen.
    /// - Note: Each value is only written when it changed, so an unchanged publish
    ///   does not invalidate any view.
    func apply(baseDetent: BaseSheetDetent, presentedRoute: MapSheetRoute) {
        if self.baseDetent != baseDetent { self.baseDetent = baseDetent }
        if self.presentedRoute != presentedRoute { self.presentedRoute = presentedRoute }
    }

    /// Publishes whether the base sheet is too short to show content below its search bar.
    ///
    /// - Parameter hidesBaseSheetContent: `true` while the sheet is collapsed.
    func apply(hidesBaseSheetContent: Bool) {
        guard self.hidesBaseSheetContent != hidesBaseSheetContent else { return }
        self.hidesBaseSheetContent = hidesBaseSheetContent
    }
}
