//
//  SheetHostingControllers.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import SwiftUI
import UIKit

// MARK: - Hosting controllers

/// Reports once when its sheet gained a container view, so the controller can
/// size and position it before the presentation animation starts.
final class SheetNavigationController: UINavigationController {

    /// Called exactly once, with this controller, as soon as its sheet has a container
    /// view to size and position.
    var containerViewDidInitialize: ((UIViewController) -> Void)?

    private var didReportContainerView = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        addBackdrop()
    }

    /// Lays a material behind the content so the sheet carries its own glass.
    ///
    /// The sheet's default chrome is drawn by the presentation container and follows the
    /// presenting controller, which over the globe still resolves to the app's light
    /// appearance - a white slab over a dark globe. A material inside the controller does
    /// follow this controller's `overrideUserInterfaceStyle`, so it covers the slab with
    /// glass that matches what is behind the sheet.
    private func addBackdrop() {

        let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(backdrop, at: 0)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard !didReportContainerView, sheetPresentationController?.containerView != nil else { return }
        didReportContainerView = true
        containerViewDidInitialize?(self)
    }
}

/// Hosting controller for sheet content that reports its container view once and its
/// height continuously.
///
/// The height signal is what decides whether the base sheet's content is visible; it
/// is taken from the real bounds so it is correct mid-drag, where the selected detent
/// has not changed yet.
/// Layout constants for ``SheetViewController``.
///
/// Declared at file scope because `SheetViewController` is generic, and Swift does not allow
/// static stored properties inside a generic type.
private enum SheetMetrics {

    /// Height changes below this (points) are not reported.
    static let heightChangeTolerance: CGFloat = 0.5
}

final class SheetViewController<Content: View>: UIHostingController<Content> {

    /// Called exactly once, with this controller, as soon as its sheet has a container
    /// view to size and position.
    var containerViewDidInitialize: ((UIViewController) -> Void)?

    /// Fires whenever the sheet settles on a new height, including continuously
    /// while the user drags it between detents.
    var heightDidChange: ((CGFloat) -> Void)?

    private var didReportContainerView = false

    /// `.nan` until the first layout pass, so the first height is always reported.
    private var lastReportedHeight: CGFloat = .nan

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard !didReportContainerView, sheetPresentationController?.containerView != nil else { return }
        didReportContainerView = true
        containerViewDidInitialize?(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let height = view.bounds.height

        // Negated deliberately: with `lastReportedHeight` still `.nan` the comparison is
        // false, so the negation lets the very first height through. Rewriting this as
        // `>= tolerance` would make the NaN comparison false and swallow that report.
        guard !(abs(height - lastReportedHeight) < SheetMetrics.heightChangeTolerance) else { return }
        lastReportedHeight = height
        heightDidChange?(height)
    }
}
