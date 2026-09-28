//
//  MapDetailRequest.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// What a map is asked to do, and therefore how much geometry it needs.
///
/// ``FlatMapView`` used to take the three switches below as separate initialiser parameters and
/// derive its level of detail from them in a private computed property. That worked, but it put
/// the rule out of reach of a test: nothing outside the view could ask what a given call site
/// resolves to, so "the dashboard preview stays cheap" was an intention rather than a fact.
///
/// Bundling the switches makes the rule addressable. The presets below are the combinations the
/// app actually uses, the call sites name them instead of spelling the switches out, and
/// `MapPerformanceBudgetTests` asserts what each one resolves to. A future ticket that wants the
/// preview to carry labels has to change ``preview`` to say so, and the test that guards the
/// budget fails on the same commit.
///
/// - Note: `nonisolated` because ``variant`` is read while preparing work for
///   ``FlatMapShapeCache``, which is an actor.
nonisolated struct MapDetailRequest: Hashable, Sendable {

    // MARK: - Properties

    /// Whether tapping a country selects it and the selection is highlighted.
    let selectionEnabled: Bool

    /// Whether pan, pinch and double-tap move the camera.
    let interactiveEnabled: Bool

    /// Whether country labels are drawn.
    let labelsEnabled: Bool

    // MARK: - Init

    /// Creates a detail request.
    ///
    /// - Parameters:
    ///   - selectionEnabled: Enables selection and hit-testing. Defaults to `true`.
    ///   - interactiveEnabled: Enables the gestures that move the camera. Defaults to `false`.
    ///   - labelsEnabled: Draws country labels. Defaults to `true`.
    init(selectionEnabled: Bool = true,
         interactiveEnabled: Bool = false,
         labelsEnabled: Bool = true) {

        self.selectionEnabled = selectionEnabled
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
    }

    // MARK: - Presets

    /// A map that is only looked at: the dashboard card and the onboarding welcome screen.
    ///
    /// All three switches are off, which is what resolves ``variant`` to
    /// ``FlatMapShapeCache/Variant/light``. Turning any of them on here makes every preview in
    /// the app build full-detail geometry.
    static let preview = MapDetailRequest(selectionEnabled: false,
                                          interactiveEnabled: false,
                                          labelsEnabled: false)

    /// The full map screen: selectable, pannable, labelled.
    static let interactive = MapDetailRequest(selectionEnabled: true,
                                              interactiveEnabled: true,
                                              labelsEnabled: true)

    // MARK: - Derived detail

    /// Level of detail ``FlatMapShapeCache`` is asked for.
    ///
    /// Reduced geometry is enough for a map nobody can zoom into, select from or read labels on;
    /// anything else would be detail that cannot be seen.
    ///
    /// - Returns: ``FlatMapShapeCache/Variant/light`` when none of the three switches is on,
    ///   ``FlatMapShapeCache/Variant/overview`` otherwise. Never ``full``: since [D-11] the
    ///   full geometry is fetched by ``FlatMapViewModel`` once the camera is zoomed past the
    ///   point where it can be seen, not by the call site.
    var variant: FlatMapShapeCache.Variant {

        guard selectionEnabled || interactiveEnabled || labelsEnabled else { return .light }

        return .overview
    }
}
