//
//  MapSheetCoordinator.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import SwiftUI
import UIKit

/// Owns the map's stacked sheet chain: the base search sheet, the country and appearance
/// sheets presented on top of it, and all of their geometry.
///
/// UIKit is used for this one reason - the design needs a stacked
/// `UISheetPresentationController` chain that SwiftUI cannot express. Keeping it in its own
/// type leaves ``MapViewController`` with the two jobs it is actually for: hosting the SwiftUI
/// map, and adapting the UIKit lifecycle and rotation callbacks that the chain needs.
///
/// State flows in exactly one direction per value:
///
///     intent (model.route, model.isSearchFieldFocused)
///         -> syncSheetStack() / syncBaseSheetWithSearchFocus()
///         -> UIKit presentations + detents
///         -> publishSheetState() / publishContentVisibility()
///         -> model.baseDetent, model.presentedRoute, model.hidesBaseSheetContent
///         -> SwiftUI reads them
///
/// This type is the only writer of the presentation half. Nothing in the SwiftUI layer writes
/// it back, so the two layers can never disagree about what is on screen.
///
/// - Note: Several methods here carry comments recording measured regressions - the rotation
///   path in particular. They moved out of ``MapViewController`` unchanged apart from the
///   receiver, and are meant to stay that way; measure before changing them.
@MainActor
final class MapSheetCoordinator: NSObject {

    // MARK: - Dependencies

    /// The controller the sheets are presented from.
    ///
    /// - Note: `unowned` rather than `weak`: the host owns this coordinator, so it cannot
    ///   outlive the host, and the moved code reads the host's geometry on nearly every line.
    private unowned let host: MapViewController

    /// The map's state. Only the intent half is read here; the presentation half is written.
    private let model: MapScreenModel

    /// SwiftData context handed to every presented sheet.
    private let modelContext: ModelContext

    // MARK: - Presentation state

    private var baseSheetViewController: SheetViewController<AnyView>?
    private var secondarySheetViewController: UINavigationController?

    /// What `secondarySheetViewController` is currently showing. The single piece
    /// of presentation bookkeeping this type keeps; everything else is read back
    /// off UIKit.
    private var presentedRoute: MapSheetRoute = .none

    /// Detent the base sheet rested on before a secondary sheet pushed it down to `.small`.
    private var storedBaseDetentIdentifier: UISheetPresentationController.Detent.Identifier?

    /// True between starting a secondary-sheet dismissal and its completion.
    /// `syncSheetStack()` bails out while set and is re-run afterwards, so the
    /// stack converges on `model.route` one presentation at a time.
    private var isTransitioningSecondarySheet = false

    /// Set from ``hostWillDisappear()`` until the next ``hostDidAppear()``. Every presenting
    /// path checks it so nothing is put up on a controller that is leaving.
    private var isExiting = false

    /// Whether the current expanded base sheet was raised by the search field rather
    /// than by the user, which is the only case this type lowers again.
    private var didExpandBaseSheetForSearch = false

    /// Rotation guard. Everything geometry-related reads this to decide between the
    /// soft treatment (during the turn) and the hard one (once it has settled).
    private var isInSizeTransition = false

    /// Invisible one-point view the sheets are anchored to, so they can be pinned to
    /// the leading edge instead of being centred.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in ``attach()`` and is never
    ///   nil afterwards for the coordinator's lifetime, which is the pattern Apple prescribes
    ///   for programmatically created views.
    private var bottomSheetAnchorView: UIView!

    /// Horizontal position of ``bottomSheetAnchorView``, re-evaluated on every layout
    /// pass and during rotation.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in ``attach()`` and is never
    ///   nil afterwards for the coordinator's lifetime, which is the pattern Apple prescribes
    ///   for programmatically created views.
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!

    // MARK: Layout constants

    /// Gap between the leading safe-area edge and the sheet panel.
    private let leftPadding: CGFloat = 0

    /// Identifier of the custom collapsed detent of the base sheet.
    private static let smallDetentIdentifier = UISheetPresentationController.Detent.Identifier("small")

    /// Height of the collapsed base sheet: exactly the search bar plus its padding.
    private static let collapsedSheetHeight: CGFloat = 84

    /// Detent identifier shared by every secondary sheet; each one has a single,
    /// fixed-height detent.
    private static let secondarySheetDetentIdentifier =
        UISheetPresentationController.Detent.Identifier("secondary")

    /// Side length of the invisible sheet anchor view. Only its position matters,
    /// so it is kept as small as a layout-engine-visible view can be.
    private static let anchorViewSideLength: CGFloat = 1

    /// Share of the available width the sheet panel takes when it is edge-attached
    /// instead of full-width.
    private static let attachedSheetWidthFraction: CGFloat = 0.4

    /// Fraction used to convert a width into its centre offset.
    private static let centerFraction: CGFloat = 0.5

    /// Geometry differences below this (points) are not worth a layout pass.
    private static let layoutMismatchTolerance: CGFloat = 1.0

    /// Slack (points) added around the window when testing whether the sheet
    /// container has left the screen entirely.
    private static let offscreenProbeSlack: CGFloat = 20

    /// Tolerance (points) applied to the collapsed height comparison, so a sheet
    /// resting on the collapsed detent still counts as collapsed after rounding.
    private static let collapsedHeightTolerance: CGFloat = 1

    /// Fixed height of the country quick-action sheet.
    private static let countrySheetDetentHeight: CGFloat = 210

    /// Fixed height of the map appearance sheet.
    private static let appearanceSheetDetentHeight: CGFloat = 130

    /// Accessibility identifier of a secondary sheet's close button.
    static let sheetCloseButtonIdentifier = "mapSheetCloseButton"

    /// Whether a sheet may be presented right now: the controller is on screen, is
    /// not being torn down, and nothing is presented yet.
    private var canPresent: Bool {
        !isExiting && host.isViewLoaded && host.view.window != nil && host.presentedViewController == nil
    }

    // MARK: - Init

    /// Creates the coordinator for one map screen.
    ///
    /// - Parameters:
    ///   - host: The controller the sheets are presented from.
    ///   - model: The map's state; the coordinator writes its presentation half.
    ///   - modelContext: SwiftData context handed to every presented sheet.
    init(host: MapViewController, model: MapScreenModel, modelContext: ModelContext) {
        self.host = host
        self.model = model
        self.modelContext = modelContext
        super.init()
    }

    // MARK: - Host lifecycle

    /// Installs the sheet anchor and starts watching the model. Called once, from the host's
    /// `viewDidLoad()`.
    func attach() {
        addBottomSheetAnchorView()
        startObservingModel()
    }

    /// Clears the exit guard set by a previous departure and brings the base sheet up.
    func hostDidAppear() {
        isExiting = false
        presentBaseSheetIfNeeded()
    }

    /// Sets the exit guard and tears the sheets down before the host detaches, so nothing is
    /// left presented on a view controller that is going away.
    func hostWillDisappear() {
        isExiting = true
        tearDownSheets()
    }

    /// Keeps the anchor and the sheet geometry correct for any layout change that is not a
    /// rotation, for example a safe-area or window-size change.
    func hostDidLayoutSubviews() {
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        updateSheetLayout()
    }

    // MARK: - Rotation

    /// Rotation handling: geometry is updated inside the coordinator's animation
    /// block so it interpolates with the turn, plus one stabilising pass in the
    /// completion.
    ///
    /// Verified against a frame-by-frame recording - the sheet stays visible for
    /// every frame of the turn in both directions. Several attempts to reason this
    /// out without one produced regressions instead, so measure before changing it:
    /// `xcrun simctl io booted recordVideo` plus a log of `applyPreferredLayout`
    /// shows immediately whether the geometry is moving during the turn or jumping
    /// after it.
    ///
    /// - Parameters:
    ///   - size: The size the host's view is transitioning to.
    ///   - coordinator: The host's transition coordinator, already running.
    func hostWillTransition(to size: CGSize,
                            with coordinator: UIViewControllerTransitionCoordinator) {

        isInSizeTransition = true

        let sheet = baseSheetViewController?.sheetPresentationController
        let targetDetent = remappedDetent(forRotationTo: size, current: sheet?.selectedDetentIdentifier)

        // A detent remembered for after a secondary sheet closes has to follow the
        // same remap, otherwise restoring it would drop the sheet back into the
        // detent the new orientation just rejected.
        storedBaseDetentIdentifier = remappedDetent(forRotationTo: size, current: storedBaseDetentIdentifier)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let strong = self else { return }

            // During transition: only "soft" changes.
            strong.bottomSheetAnchorCenterXConstraint.constant = strong.bottomSheetAnchorCenterXConstant
            strong.updateSheetLayout()
            strong.layoutVisibleSheetNavigationBars(hard: false)

            // Already inside an animation context - no `animateChanges` wrapper.
            if let sheet, let targetDetent, sheet.selectedDetentIdentifier != targetDetent {
                sheet.selectedDetentIdentifier = targetDetent
            }

        }, completion: { [weak self] _ in
            guard let strong = self else { return }
            strong.isInSizeTransition = false

            // Final: one hard stabilize.
            strong.bottomSheetAnchorCenterXConstraint.constant = strong.bottomSheetAnchorCenterXConstant
            strong.updateSheetLayout()
            strong.layoutVisibleSheetNavigationBars(hard: true)
            strong.publishSheetState()
        })
    }

    /// There is no half-height state in landscape - the screen is too short for it to
    /// mean anything, and UIKit does not offer `.medium` in a compact height anyway.
    /// So the expanded sheet is `.medium` in portrait and `.large` in landscape, and
    /// a rotation maps one onto the other. Collapsed stays collapsed either way.
    ///
    /// Derived from the target `size` rather than a trait collection, so it needs no
    /// state carried across the transition.
    ///
    /// - Parameters:
    ///   - size: The size the view is transitioning to.
    ///   - current: The detent identifier in effect before the rotation.
    /// - Returns: The identifier to use in the new orientation, or `current`
    ///   unchanged when it is valid in both.
    private func remappedDetent(forRotationTo size: CGSize,
                                current: UISheetPresentationController.Detent.Identifier?)
    -> UISheetPresentationController.Detent.Identifier? {

        let becomesPortrait = size.height > size.width

        switch (becomesPortrait, current) {
        case (true, .large):  return .medium
        case (false, .medium): return .large
        default:              return current
        }
    }

    /// Walks the presented sheet chain and re-lays out the navigation bars it finds.
    ///
    /// Stacked sheets are navigation controllers; their bars need the same soft
    /// during / hard after treatment or they lay out at the old width.
    ///
    /// - Parameter hard: `true` lays the bars out immediately, `false` only marks
    ///   them as needing layout so the change interpolates with the rotation.
    private func layoutVisibleSheetNavigationBars(hard: Bool) {

        var controller: UIViewController? = baseSheetViewController?.presentedViewController

        while let current = controller {
            if let navigationController = current as? UINavigationController {
                navigationController.navigationBar.setNeedsLayout()
                navigationController.view.setNeedsLayout()
                if hard {
                    navigationController.navigationBar.layoutIfNeeded()
                    navigationController.view.layoutIfNeeded()
                }
            }
            controller = current.presentedViewController
        }
    }

    // MARK: - Model observation

    /// Observes the intent half of ``MapScreenModel`` and reconciles the sheet stack
    /// with it.
    ///
    /// - Note: Re-registers after every change; `withObservationTracking` is single-shot.
    private func startObservingModel() {
        withObservationTracking {
            _ = model.route
            _ = model.isSearchFieldFocused
            _ = model.appearance
        } onChange: { [weak self] in
            // onChange fires *before* the value is written, so hop to the next turn.
            Task { @MainActor [weak self] in
                guard let strong = self,
                      !strong.isExiting
                else { return }
                strong.startObservingModel()
                strong.syncBaseSheetWithSearchFocus()
                strong.syncSheetStack()
                strong.applySheetInterfaceStyle()
            }
        }
    }

    // MARK: - Sheet appearance

    /// Interface style the sheets take, given what is behind them.
    ///
    /// The globe is Apple's satellite imagery and is dark whatever the app's appearance is.
    /// A light sheet over it reads as a white slab rather than as glass, so the sheets follow
    /// the backdrop instead of the app: dark over the globe, the app's own style over the
    /// flat map.
    private var sheetInterfaceStyle: UIUserInterfaceStyle {
        model.appearance == .threeD ? .dark : .unspecified
    }

    /// Applies ``sheetInterfaceStyle`` to every sheet currently on screen.
    private func applySheetInterfaceStyle() {

        let style = sheetInterfaceStyle

        // Set on the presenting controller, not only on the sheets: a sheet's own chrome -
        // the glass slab behind the content - is drawn by the presentation container, which
        // follows the presenting trait collection rather than the presented view's override.
        host.overrideUserInterfaceStyle = style
        baseSheetViewController?.overrideUserInterfaceStyle = style
        baseSheetViewController?.presentedViewController?.overrideUserInterfaceStyle = style
    }

    // MARK: - Anchor

    /// Adds the invisible view the sheets use as their `sourceView`.
    ///
    /// Anchoring to a view is what lets the sheet sit at the leading edge instead of
    /// being centred; the anchor itself is inert and never receives touches.
    private func addBottomSheetAnchorView() {

        let anchorView = UIView()
        anchorView.translatesAutoresizingMaskIntoConstraints = false
        anchorView.backgroundColor = .clear
        anchorView.isUserInteractionEnabled = false

        host.view.addSubview(anchorView)

        NSLayoutConstraint.activate([
            anchorView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            anchorView.widthAnchor.constraint(equalToConstant: Self.anchorViewSideLength),
            anchorView.heightAnchor.constraint(equalToConstant: Self.anchorViewSideLength)
        ])

        bottomSheetAnchorCenterXConstraint = anchorView.centerXAnchor.constraint(
            equalTo: host.view.safeAreaLayoutGuide.leftAnchor,
            constant: bottomSheetAnchorCenterXConstant
        )
        bottomSheetAnchorCenterXConstraint.isActive = true

        bottomSheetAnchorView = anchorView
    }

    // MARK: - Sheet sizing

    /// Portrait (phone) uses a normal full-width sheet; everything else pins a
    /// narrower panel to the leading edge.
    ///
    /// The orientation test reads `view.bounds`, deliberately, and not the vertical
    /// size class: the two do not flip at the same instant during a rotation. Bounds
    /// change early, size classes late. Deciding *which formula* from the traits
    /// while feeding it *which bounds* from the geometry meant that for a few frames
    /// on the way back to portrait the landscape formula ran on portrait bounds -
    /// `(402 - 0) * 0.4 = 161pt` - and the sheet collapsed to a sliver before
    /// springing out to full width.
    ///
    /// `userInterfaceIdiom` is safe to mix in: unlike a size class it cannot change
    /// mid-rotation.
    private var isSheetCentered: Bool {
        host.traitCollection.userInterfaceIdiom == .phone && host.view.bounds.height > host.view.bounds.width
    }

    /// Size the sheets are asked to adopt: full width when centred, a narrow panel
    /// otherwise. The height is the full view height; the detents cut it down.
    private var preferredSheetContentSize: CGSize {
        let width = isSheetCentered
            ? host.view.bounds.width
            : (host.view.bounds.width - host.view.safeAreaInsets.left) * Self.attachedSheetWidthFraction
        return CGSize(width: width, height: host.view.bounds.height)
    }

    /// Offset of ``bottomSheetAnchorView`` from the leading safe-area edge: half the
    /// sheet width, so the sheet centres on the anchor and ends up flush left.
    private var bottomSheetAnchorCenterXConstant: CGFloat {
        preferredSheetContentSize.width * Self.centerFraction + leftPadding
    }

    /// Re-applies the preferred layout to the base sheet and every sheet stacked on it.
    private func updateSheetLayout() {
        guard let base = baseSheetViewController else { return }

        applyPreferredLayout(to: base)

        var current = base.presentedViewController
        while let viewController = current {
            applyPreferredLayout(to: viewController)
            current = viewController.presentedViewController
        }
    }

    /// Sizes and positions the sheet's container view. Unchanged from before the
    /// refactor, down to the guards: the sheet's horizontal box is owned here in
    /// every orientation, which is what keeps the width from being handed to UIKit's
    /// edge-attachment logic and cut in one step at the end of a rotation.
    ///
    /// - Parameter viewController: The presented sheet whose container view is sized
    ///   and positioned.
    private func applyPreferredLayout(to viewController: UIViewController) {

        let preferredSize = preferredSheetContentSize
        viewController.preferredContentSize = preferredSize

        guard let containerView = viewController.sheetPresentationController?.containerView else { return }

        // No early return on a zero-width container: UIKit zeroes it during rotation,
        // and skipping the update there is what made the sheet snap back afterwards.

        let desiredCenterX: CGFloat = {
            if isSheetCentered {
                return host.view.bounds.midX
            } else {
                return host.view.safeAreaInsets.left + leftPadding + preferredSize.width * Self.centerFraction
            }
        }()

        let applyFix: () -> Void = {
            let centerY = containerView.center.y
            containerView.center = CGPoint(x: desiredCenterX, y: centerY)
            containerView.bounds = CGRect(origin: .zero, size: preferredSize)

            // Lay out now, not just mark dirty: deferring kept the sheet's landscape
            // geometry for three measured frames after the rotation, then it snapped.
            containerView.layoutIfNeeded()
        }

        let widthMismatch = abs(containerView.bounds.width - preferredSize.width) > Self.layoutMismatchTolerance
        let xMismatch = abs(containerView.center.x - desiredCenterX) > Self.layoutMismatchTolerance

        let offscreen: Bool = {
            if let window = containerView.window ?? host.view.window {
                let frameInWindow = containerView.convert(containerView.bounds, to: window)
                let probe = window.bounds.insetBy(dx: -Self.offscreenProbeSlack,
                                                  dy: -Self.offscreenProbeSlack)
                return !frameInWindow.intersects(probe)
            }
            return false
        }()

        guard widthMismatch || xMismatch || offscreen else { return }

        if isInSizeTransition {
            // Called from inside the transition coordinator's animation block, so the
            // geometry interpolates with the turn. Suppressing animation here - as the
            // old code did unconditionally - turns the same change into a hard cut.
            applyFix()
        } else {
            // Steady-state corrections are not events the user should see.
            UIView.performWithoutAnimation { applyFix() }
        }
    }

    // MARK: - Base sheet

    /// Presents the search sheet that is the root of the stack, unless it is already
    /// up or the controller is not in a state to present.
    private func presentBaseSheetIfNeeded() {

        guard canPresent, baseSheetViewController == nil else { return }

        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        host.view.layoutIfNeeded()

        let content = AnyView(
            DefaultSearchView(model: model)
                .environment(\.modelContext, modelContext)
        )

        let sheetViewController = SheetViewController(rootView: content)
        sheetViewController.isModalInPresentation = true
        sheetViewController.overrideUserInterfaceStyle = sheetInterfaceStyle
        sheetViewController.preferredContentSize = preferredSheetContentSize
        sheetViewController.containerViewDidInitialize = { [weak self] controller in
            self?.applyPreferredLayout(to: controller)
        }
        // The one signal that decides whether the sheet content is visible. Taken
        // from the sheet's real height so it is right mid-drag too, where the
        // selected detent has not changed yet.
        sheetViewController.heightDidChange = { [weak self] height in
            self?.publishContentVisibility(forSheetHeight: height)
        }

        if let sheet = sheetViewController.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: Self.smallDetentIdentifier) { _ in Self.collapsedSheetHeight },
                .medium(),
                .large()
            ]
            // Opens collapsed, like Apple Maps: just the search bar above the map.
            sheet.selectedDetentIdentifier = Self.smallDetentIdentifier
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
            sheet.sourceView = bottomSheetAnchorView
            sheet.largestUndimmedDetentIdentifier = .large
            sheet.delegate = self
        }

        baseSheetViewController = sheetViewController
        publishSheetState()

        host.present(sheetViewController, animated: true) { [weak self] in
            guard let strong = self else { return }
            strong.applyPreferredLayout(to: sheetViewController)
            strong.publishSheetState()
            // Selection may have arrived while the base sheet was animating in.
            strong.syncSheetStack()
        }
    }

    /// Drops the whole sheet stack and resets every piece of presentation
    /// bookkeeping, so leaving and re-entering the map starts from a clean state.
    func tearDownSheets() {

        if host.presentedViewController != nil {
            host.dismiss(animated: false)
        }

        isInSizeTransition = false

        baseSheetViewController = nil
        secondarySheetViewController = nil
        presentedRoute = .none
        storedBaseDetentIdentifier = nil
        isTransitioningSecondarySheet = false
        didExpandBaseSheetForSearch = false

        model.route = .none
        model.apply(hidesBaseSheetContent: true)
        publishSheetState()
    }

    // MARK: - Secondary sheets

    /// Converges the presented stack on `model.route`, one step per call: if
    /// something wrong is up it is dismissed and this runs again from the
    /// completion. That single loop covers open, close and the country/appearance
    /// swap, which used to be three separate branches that could interleave.
    private func syncSheetStack() {

        guard !isExiting, host.isViewLoaded, host.view.window != nil else { return }
        guard !isTransitioningSecondarySheet else { return }

        // The base sheet is the root of the stack; without it there is nothing to present on.
        guard baseSheetViewController != nil else {
            presentBaseSheetIfNeeded()
            return
        }

        let desired = model.route

        // Same kind of sheet, different country: swap the content, keep the sheet.
        if let country = desired.country,
           presentedRoute.country != nil,
           let sheetHost = secondarySheetViewController?.viewControllers.first as? SheetViewController<AnyView> {

            sheetHost.navigationItem.title = country.displayName
            sheetHost.rootView = countrySheetContent(for: country)
            presentedRoute = .country(country)
            updateBaseSheetDetentForStack()
            publishSheetState()
            return
        }

        guard desired != presentedRoute else {
            updateBaseSheetDetentForStack()
            publishSheetState()
            return
        }

        // Something else is up: take it down first, then run again to present the
        // sheet that is actually wanted.
        if let presented = secondarySheetViewController {

            isTransitioningSecondarySheet = true
            secondarySheetViewController = nil
            presentedRoute = .none

            presented.dismiss(animated: true) { [weak self] in
                guard let strong = self else { return }
                strong.isTransitioningSecondarySheet = false
                strong.publishSheetState()
                strong.syncSheetStack()
            }
            return
        }

        // Nothing up: collapse the base sheet first so the new sheet slides onto a
        // settled stack, then present.
        updateBaseSheetDetentForStack()

        switch desired {
        case .none:
            break

        case .country(let country):
            secondarySheetViewController = presentSheet(
                content: countrySheetContent(for: country),
                title: country.displayName,
                detentHeight: Self.countrySheetDetentHeight
            ) { [weak self] in
                self?.model.route = .none
            }
            presentedRoute = secondarySheetViewController == nil ? .none : desired

        case .appearance:
            secondarySheetViewController = presentSheet(
                content: AnyView(MapAppearancePanelView(model: model)),
                title: "Appearance",
                detentHeight: Self.appearanceSheetDetentHeight
            ) { [weak self] in
                self?.model.route = .none
            }
            presentedRoute = secondarySheetViewController == nil ? .none : desired
        }

        publishSheetState()
    }

    /// Typing needs room: raise a collapsed base sheet when the search field takes
    /// focus, and drop it back when the user leaves the field. Only sheets that
    /// *this* raised are lowered again, so a detent the user picked himself stands.
    private func syncBaseSheetWithSearchFocus() {

        guard let sheet = baseSheetViewController?.sheetPresentationController else { return }

        if model.isSearchFieldFocused {
            guard sheet.selectedDetentIdentifier == Self.smallDetentIdentifier else { return }
            didExpandBaseSheetForSearch = true
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .large
            }
            publishSheetState()
        } else if didExpandBaseSheetForSearch {
            didExpandBaseSheetForSearch = false
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = Self.smallDetentIdentifier
            }
            publishSheetState()
        }
    }

    /// Collapses the base sheet while a secondary sheet is up, restores it afterwards.
    private func updateBaseSheetDetentForStack() {

        guard let sheet = baseSheetViewController?.sheetPresentationController else { return }

        let showsSecondary = model.route != .none

        if showsSecondary {
            // Remember the detent from before *anything* was stacked on top.
            if storedBaseDetentIdentifier == nil {
                storedBaseDetentIdentifier = sheet.selectedDetentIdentifier ?? .medium
            }
            guard sheet.selectedDetentIdentifier != Self.smallDetentIdentifier else { return }
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = Self.smallDetentIdentifier
            }
        } else if let restore = storedBaseDetentIdentifier {
            storedBaseDetentIdentifier = nil
            guard sheet.selectedDetentIdentifier != restore else { return }
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = restore
            }
        }
    }

    /// Builds the quick-action content shown for a selected country.
    ///
    /// - Parameter country: The country whose actions are shown.
    /// - Returns: The sheet content, already carrying the SwiftData context.
    private func countrySheetContent(for country: Country) -> AnyView {
        AnyView(
            CountryQuickActionPanelView(country: country)
                .environment(\.modelContext, modelContext)
        )
    }

    /// Presents a secondary sheet on top of the current topmost sheet.
    ///
    /// - Parameters:
    ///   - content: SwiftUI content to host inside the sheet.
    ///   - title: Navigation bar title of the sheet.
    ///   - detentHeight: Fixed height of the sheet's single detent, in points.
    ///   - onClose: Invoked by the close button in the navigation bar.
    /// - Returns: The presented navigation controller, or `nil` when there is no base
    ///   sheet to present on.
    private func presentSheet(content: AnyView,
                              title: String,
                              detentHeight: CGFloat,
                              onClose: @escaping () -> Void) -> UINavigationController? {

        guard let base = baseSheetViewController else { return nil }

        let sheetHost = SheetViewController(rootView: content)
        sheetHost.navigationItem.title = title
        let closeButton = UIBarButtonItem(systemItem: .close,
                                          primaryAction: UIAction { _ in onClose() })
        // The map screen's own close button carries the same label, so a UI test needs
        // something else to tell the two apart.
        closeButton.accessibilityIdentifier = Self.sheetCloseButtonIdentifier
        sheetHost.navigationItem.rightBarButtonItem = closeButton

        let navigationController = SheetNavigationController(rootViewController: sheetHost)
        navigationController.overrideUserInterfaceStyle = sheetInterfaceStyle
        navigationController.preferredContentSize = preferredSheetContentSize
        navigationController.containerViewDidInitialize = { [weak self] controller in
            self?.applyPreferredLayout(to: controller)
        }

        if let sheet = navigationController.sheetPresentationController {
            let identifier = Self.secondarySheetDetentIdentifier
            sheet.detents = [.custom(identifier: identifier) { _ in detentHeight }]
            sheet.prefersGrabberVisible = false
            sheet.largestUndimmedDetentIdentifier = identifier
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.sourceView = bottomSheetAnchorView
            sheet.delegate = self
        }

        // Present on the topmost sheet so the stack keeps its order.
        var presenter: UIViewController = base
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }

        presenter.present(navigationController, animated: true) { [weak self] in
            self?.applyPreferredLayout(to: navigationController)
        }

        return navigationController
    }

    // MARK: - Publishing state back to SwiftUI

    /// Pushes the current detent and the route that is really on screen into the model.
    ///
    /// - Note: Falls back to `.small` when UIKit reports no detent, which is the state
    ///   the base sheet opens in.
    private func publishSheetState() {
        let selectedDetentIdentifier = baseSheetViewController?
            .sheetPresentationController?
            .selectedDetentIdentifier

        model.apply(
            baseDetent: Self.detent(from: selectedDetentIdentifier) ?? .small,
            presentedRoute: presentedRoute
        )
    }

    /// Collapsed, the sheet is exactly as tall as its search bar - anything below
    /// would peek out from under it. Hidden rather than pushed down: moving the
    /// content changes the scroll geometry, which is what made the list refuse to
    /// come along when the sheet was dragged up.
    ///
    /// - Parameter height: The sheet's current real height in points.
    private func publishContentVisibility(forSheetHeight height: CGFloat) {
        let collapsedThreshold = Self.collapsedSheetHeight + Self.collapsedHeightTolerance
        model.apply(hidesBaseSheetContent: height <= collapsedThreshold)
    }

    /// Maps a UIKit detent identifier onto the SwiftUI-facing ``BaseSheetDetent``.
    ///
    /// - Parameter identifier: The identifier UIKit reports, if any.
    /// - Returns: The matching detent, or `nil` for an identifier the map does not use.
    private static func detent(
        from identifier: UISheetPresentationController.Detent.Identifier?
    ) -> BaseSheetDetent? {
        switch identifier {
        case smallDetentIdentifier: return .small
        case .medium: return .medium
        case .large: return .large
        default: return nil
        }
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension MapSheetCoordinator: UISheetPresentationControllerDelegate {

    /// Keeps the sheet geometry and the published state in step with a detent change,
    /// whether it came from the user or from the controller.
    ///
    /// - Parameter sheetPresentationController: The sheet whose detent changed.
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        updateSheetLayout()
        publishSheetState()
    }

    /// Clears the bookkeeping for whichever sheet was dismissed, including dismissals
    /// the user drove by swiping the sheet away.
    ///
    /// - Parameter presentationController: The presentation controller that finished
    ///   dismissing.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {

        let dismissed = presentationController.presentedViewController

        if dismissed === secondarySheetViewController {
            secondarySheetViewController = nil
            presentedRoute = .none
            model.route = .none
        } else if dismissed === baseSheetViewController {
            baseSheetViewController = nil
        }

        publishSheetState()
    }
}
