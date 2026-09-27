//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import UIKit
import SwiftUI
import SwiftData

// MARK: - SwiftUI Bridge

/// Embeds ``MapViewController`` in the SwiftUI navigation stack.
///
/// The map screen itself is a UIKit controller because of its stacked sheet chain;
/// this representable is the only seam between it and the surrounding SwiftUI
/// navigation.
///
/// - Note: The navigation path is handed down as a binding so the controller's
///   close button can pop the very stack that pushed it.
struct MapControllerRepresentable: UIViewControllerRepresentable {

    /// Navigation path of the enclosing stack, used by the map's close button.
    @Binding var path: NavigationPath

    /// SwiftData context forwarded into the sheets the controller presents.
    @Environment(\.modelContext) private var modelContext

    /// Creates the controller and hands it the current navigation path.
    ///
    /// - Parameter context: Representable context provided by SwiftUI.
    /// - Returns: A freshly configured ``MapViewController``.
    func makeUIViewController(context: Context) -> MapViewController {
        let controller = MapViewController(modelContext: modelContext)
        controller.path = $path
        return controller
    }

    /// Re-hands the navigation path so the controller never pops a stale stack.
    ///
    /// - Parameters:
    ///   - uiViewController: The controller created by ``makeUIViewController(context:)``.
    ///   - context: Representable context provided by SwiftUI.
    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        uiViewController.path = $path
    }
}

// MARK: - MapViewController

/// Hosts the SwiftUI map and owns the stacked sheet chain around it.
///
/// UIKit is used here for one reason: the design needs a stacked
/// `UISheetPresentationController` chain (base search sheet, with country /
/// appearance sheets presented on top of it) that SwiftUI cannot express.
///
/// Everything else lives in SwiftUI and is driven by ``MapScreenModel``. The
/// hosting controller's root view is built exactly once; replacing it on every
/// state change is what previously left the map blank and the sheet stack stuck.
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
/// Nothing in the SwiftUI layer writes the presentation half back, so the two
/// layers can never disagree about what is on screen.
final class MapViewController: UIViewController {

    // MARK: State

    private let model = MapScreenModel()
    private let modelContext: ModelContext

    /// Kept fresh by `updateUIViewController` so the close button always pops the current stack.
    var path: Binding<NavigationPath>?

    // MARK: - Initialization

    /// Creates the map controller.
    ///
    /// - Parameter modelContext: SwiftData context handed to every presented sheet.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
    }

    /// Not supported: the controller is only ever created programmatically.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UI

    /// Hosting controller for the SwiftUI map.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in `viewDidLoad()`
    ///   and is never nil afterwards for the controller's lifetime, which is the
    ///   pattern Apple prescribes for programmatically created views.
    private var mapHost: UIHostingController<MapView>!

    private var baseSheetViewController: SheetViewController<AnyView>?
    private var secondarySheetViewController: UINavigationController?

    /// What `secondarySheetViewController` is currently showing. The single piece
    /// of presentation bookkeeping the controller keeps; everything else is read
    /// back off UIKit.
    private var presentedRoute: MapSheetRoute = .none

    /// Detent the base sheet rested on before a secondary sheet pushed it down to `.small`.
    private var storedBaseDetentIdentifier: UISheetPresentationController.Detent.Identifier?

    /// True between starting a secondary-sheet dismissal and its completion.
    /// `syncSheetStack()` bails out while set and is re-run afterwards, so the
    /// stack converges on `model.route` one presentation at a time.
    private var isTransitioningSecondarySheet = false

    /// Set from `viewWillDisappear` until the next `viewDidAppear`. Every presenting
    /// path checks it so nothing is put up on a controller that is leaving.
    private var isExiting = false

    /// Whether the current expanded base sheet was raised by the search field rather
    /// than by the user, which is the only case the controller lowers again.
    private var didExpandBaseSheetForSearch = false

    /// Rotation guard. Everything geometry-related reads this to decide between the
    /// soft treatment (during the turn) and the hard one (once it has settled).
    private var isInSizeTransition = false

    /// Invisible one-point view the sheets are anchored to, so they can be pinned to
    /// the leading edge instead of being centred.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in `viewDidLoad()`
    ///   and is never nil afterwards for the controller's lifetime, which is the
    ///   pattern Apple prescribes for programmatically created views.
    private(set) var bottomSheetAnchorView: UIView!

    /// Horizontal position of ``bottomSheetAnchorView``, re-evaluated on every layout
    /// pass and during rotation.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in `viewDidLoad()`
    ///   and is never nil afterwards for the controller's lifetime, which is the
    ///   pattern Apple prescribes for programmatically created views.
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

    /// Whether a sheet may be presented right now: the controller is on screen, is
    /// not being torn down, and nothing is presented yet.
    private var canPresent: Bool {
        !isExiting && isViewLoaded && view.window != nil && presentedViewController == nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpMapHost()
        addBottomSheetAnchorView()
        startObservingModel()
    }

    /// Clears the exit guard set by a previous departure and brings the base sheet up.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isExiting = false
        presentBaseSheetIfNeeded()
    }

    /// Sets the exit guard and tears the sheets down before the controller detaches,
    /// so nothing is left presented on a view controller that is going away.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isExiting = true
        tearDownSheets()
    }

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
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

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

    /// Keeps the anchor and the sheet geometry correct for any layout change that is
    /// not a rotation, for example a safe-area or window-size change.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        updateSheetLayout()
    }

    // MARK: - Navigation

    /// Leaves the map screen: tears the sheet stack down first, then pops the
    /// navigation path so no sheet outlives its controller.
    func closeMap() {
        guard let path, !path.wrappedValue.isEmpty else { return }
        tearDownSheets()
        path.wrappedValue.removeLast()
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
        } onChange: { [weak self] in
            // onChange fires *before* the value is written, so hop to the next turn.
            Task { @MainActor [weak self] in
                guard let strong = self,
                      !strong.isExiting
                else { return }
                strong.startObservingModel()
                strong.syncBaseSheetWithSearchFocus()
                strong.syncSheetStack()
            }
        }
    }

    // MARK: - Map host

    /// Builds the SwiftUI map once and pins it to the controller's view.
    ///
    /// - Note: The root view is never replaced afterwards; rebuilding it on state
    ///   changes is what previously left the map blank.
    private func setUpMapHost() {

        let rootView = MapView(model: model) { [weak self] in
            self?.closeMap()
        }

        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        host.didMove(toParent: self)
        mapHost = host
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

        view.addSubview(anchorView)

        NSLayoutConstraint.activate([
            anchorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            anchorView.widthAnchor.constraint(equalToConstant: Self.anchorViewSideLength),
            anchorView.heightAnchor.constraint(equalToConstant: Self.anchorViewSideLength)
        ])

        bottomSheetAnchorCenterXConstraint = anchorView.centerXAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leftAnchor,
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
        traitCollection.userInterfaceIdiom == .phone && view.bounds.height > view.bounds.width
    }

    /// Size the sheets are asked to adopt: full width when centred, a narrow panel
    /// otherwise. The height is the full view height; the detents cut it down.
    private var preferredSheetContentSize: CGSize {
        let width = isSheetCentered
            ? view.bounds.width
            : (view.bounds.width - view.safeAreaInsets.left) * Self.attachedSheetWidthFraction
        return CGSize(width: width, height: view.bounds.height)
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
                return view.bounds.midX
            } else {
                return view.safeAreaInsets.left + leftPadding + preferredSize.width * Self.centerFraction
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
            if let window = containerView.window ?? view.window {
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
        view.layoutIfNeeded()

        let content = AnyView(
            DefaultSearchView(model: model)
                .environment(\.modelContext, modelContext)
        )

        let sheetViewController = SheetViewController(rootView: content)
        sheetViewController.isModalInPresentation = true
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

        present(sheetViewController, animated: true) { [weak self] in
            guard let strong = self else { return }
            strong.applyPreferredLayout(to: sheetViewController)
            strong.publishSheetState()
            // Selection may have arrived while the base sheet was animating in.
            strong.syncSheetStack()
        }
    }

    /// Drops the whole sheet stack and resets every piece of presentation
    /// bookkeeping, so leaving and re-entering the map starts from a clean state.
    private func tearDownSheets() {

        if presentedViewController != nil {
            dismiss(animated: false)
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

        guard !isExiting, isViewLoaded, view.window != nil else { return }
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
           let host = secondarySheetViewController?.viewControllers.first as? SheetViewController<AnyView> {

            host.navigationItem.title = country.nameEnglish
            host.rootView = countrySheetContent(for: country)
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
                title: country.nameEnglish,
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
            CountryQuickActionPanelView(country: country) { [weak self] in
                self?.model.route = .none
            }
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

        let host = SheetViewController(rootView: content)
        host.navigationItem.title = title
        host.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { _ in onClose() }
        )

        let navigationController = SheetNavigationController(rootViewController: host)
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

extension MapViewController: UISheetPresentationControllerDelegate {

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
