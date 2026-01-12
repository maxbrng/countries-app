//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import UIKit
import SwiftUI
import MapKit

// MARK: - SwiftUI Bridge

struct MapControllerRepresentable: UIViewControllerRepresentable {
    @Binding var path: NavigationPath

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MapViewController {
        let controller = MapViewController()
        controller.path = $path
        return controller
    }

    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        uiViewController.path = $path

        // Optional: if you pop to root via NavigationPath updates, dismiss immediately
        context.coordinator.handlePathUpdate(path, controller: uiViewController)
    }

    final class Coordinator {
        private var lastCount: Int?

        func handlePathUpdate(_ path: NavigationPath, controller: MapViewController) {
            let newCount = path.count
            defer { lastCount = newCount }

            guard let old = lastCount else { return }

            // Only act when path drops to 0 (return to root)
            if newCount == 0, old > 0 {
                controller.dismissSheetsImmediatelyForExit()
            }
        }
    }
}

// MARK: - MapViewController

final class MapViewController: UIViewController, UINavigationControllerDelegate {

    // MARK: - State
    var path: Binding<NavigationPath>!
    private var selectedCountry: Country? { didSet { syncStack() } }
    private var showAppearancePanel: Bool = false { didSet { syncStack() } }
    private var appearance: MapAppearance = .twoD { didSet { rebuildMapRoot() } }

    // MARK: - UI
    private var mapHost: UIHostingController<AnyView>!

    // Keep strong refs (stacking / iOS quirks)
    private var baseBottomSheetViewController: SheetViewController<AnyView>?
    private var countrySheetVC: UIViewController?
    private var appearanceSheetVC: UIViewController?

    // MARK: - Anchor
    private(set) var bottomSheetAnchorView: UIView!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!

    private let leftPadding: CGFloat = 0
    private let smallDetentHeight: CGFloat = 130

    private var didPresentInitialSheet = false

    // Initial present timing
    private var initialPresentWorkItem: DispatchWorkItem?
    private let initialSheetDelay: TimeInterval = 0.0

    // Nav pop early-dismiss hooks
    private weak var previousNavDelegate: UINavigationControllerDelegate?
    private var popGestureAttached = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        addBottomSheetAnchorView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Attach early-dismiss hooks while visible
        attachNavigationEarlyDismissHooks()

        // Present base sheet at the same moment (after push completes), but with no bottom animation
        scheduleInitialSheetPresentationIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        detachNavigationEarlyDismissHooks()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.bottomSheetAnchorCenterXConstraint.constant = self.bottomSheetAnchorCenterXConstant
            self.updateSheetsContentSizeAndPosition()
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.bottomSheetAnchorCenterXConstraint.constant = self.bottomSheetAnchorCenterXConstant
            self.updateSheetsContentSizeAndPosition()
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Order: anchor first, then update
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        updateSheetsContentSizeAndPosition()
    }

    // MARK: - Early dismiss hooks (FAST)

    private func attachNavigationEarlyDismissHooks() {
        guard let nav = navigationController else { return }

        // delegate
        if previousNavDelegate == nil { previousNavDelegate = nav.delegate }
        nav.delegate = self

        // interactive swipe-back
        if let popGesture = nav.interactivePopGestureRecognizer, !popGestureAttached {
            popGesture.addTarget(self, action: #selector(handleInteractivePop(_:)))
            popGestureAttached = true
        }
    }

    private func detachNavigationEarlyDismissHooks() {
        if let nav = navigationController {
            if nav.delegate === self {
                nav.delegate = previousNavDelegate
            }
        }

        if let popGesture = navigationController?.interactivePopGestureRecognizer, popGestureAttached {
            popGesture.removeTarget(self, action: #selector(handleInteractivePop(_:)))
            popGestureAttached = false
        }

        previousNavDelegate = nil
    }

    @objc private func handleInteractivePop(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .began else { return }
        // Earliest moment for swipe-back
        dismissSheetsImmediatelyForExit()
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        // Back button pop: willShow the previous VC. If leaving self, dismiss immediately.
        if viewController !== self {
            dismissSheetsImmediatelyForExit()
        }

        // Forward delegate if needed
        previousNavDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        previousNavDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
    }

    // MARK: - Initial present scheduling (NO animation from bottom)

    private func scheduleInitialSheetPresentationIfNeeded() {
        guard !didPresentInitialSheet else { return }
        guard view.window != nil else { return }

        initialPresentWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.didPresentInitialSheet else { return }
            guard self.view.window != nil else { return }

            self.updateAnchorNow()

            // Show instantly (no bottom slide animation)
            self.presentBaseBottomSheetIfNeeded(animated: true)
            self.didPresentInitialSheet = true
        }
        initialPresentWorkItem = work

        // After push transition completes (so it doesn't appear "before" the screen lands)
        if let tc = transitionCoordinator {
            tc.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                if self.initialSheetDelay <= 0 {
                    DispatchQueue.main.async(execute: work)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.initialSheetDelay, execute: work)
                }
            }
        } else {
            if initialSheetDelay <= 0 {
                DispatchQueue.main.async(execute: work)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + initialSheetDelay, execute: work)
            }
        }
    }

    // MARK: - Immediate dismiss (callable from Coordinator/path + nav hooks)

    func dismissSheetsImmediatelyForExit() {
        // cancel pending present
        initialPresentWorkItem?.cancel()
        initialPresentWorkItem = nil

        // dismiss whole chain immediately
        if presentedViewController != nil {
            dismiss(animated: false)
        }

        baseBottomSheetViewController = nil
        countrySheetVC = nil
        appearanceSheetVC = nil

        didPresentInitialSheet = false
        selectedCountry = nil
        showAppearancePanel = false
    }

    // MARK: - Preferred size (same logic as original)
    private var isSheetCentered: Bool {
        traitCollection.horizontalSizeClass == .compact &&
        traitCollection.verticalSizeClass == .regular
    }

    var preferredSheetContentSize: CGSize {
        let width = isSheetCentered
            ? view.bounds.width
            : (view.bounds.width - view.safeAreaInsets.left) * 0.5
        return .init(width: width, height: view.bounds.height)
    }

    var bottomSheetAnchorCenterXConstant: CGFloat {
        preferredSheetContentSize.width * 0.5 + leftPadding
    }

    private func updateAnchorNow() {
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        view.layoutIfNeeded()
    }

    // MARK: - Update sheet sizes (supports stacking)
    private func updateSheetsContentSizeAndPosition() {
        guard let base = baseBottomSheetViewController else { return }

        updateContentSizeAndPosition(forSheetViewController: base)

        var current = base.presentedViewController
        while let vc = current {
            updateContentSizeAndPosition(forSheetViewController: vc)
            current = vc.presentedViewController
        }
    }

    /// iOS17: always force
    /// iOS18+/iOS26: native, but repair if width/x wrong OR offscreen (rotation case)
    func updateContentSizeAndPosition(forSheetViewController viewController: UIViewController) {
        let preferredSize = preferredSheetContentSize
        viewController.preferredContentSize = preferredSize

        guard let containerView = viewController.sheetPresentationController?.containerView else { return }

        let desiredCenterX: CGFloat = {
            if isSheetCentered {
                return view.bounds.midX
            } else {
                return view.safeAreaInsets.left + leftPadding + preferredSize.width * 0.5
            }
        }()

        let applyFix: () -> Void = {
            let centerY = containerView.center.y
            containerView.center = CGPoint(x: desiredCenterX, y: centerY)
            containerView.bounds = CGRect(origin: .zero, size: preferredSize)
            containerView.layoutIfNeeded()
        }

        if #available(iOS 18, *) {
            let widthMismatch = abs(containerView.bounds.width - preferredSize.width) > 1.0
            let xMismatch = abs(containerView.center.x - desiredCenterX) > 1.0

            let offscreen: Bool = {
                if let win = containerView.window ?? view.window {
                    let frameInWin = containerView.convert(containerView.bounds, to: win)
                    return !frameInWin.intersects(win.bounds.insetBy(dx: -20, dy: -20))
                }
                return false
            }()

            if widthMismatch || xMismatch || offscreen {
                UIView.performWithoutAnimation { applyFix() }
            }
            return
        }

        UIView.performWithoutAnimation { applyFix() }
    }

    // MARK: - Base Bottom Sheet
    private func presentBaseBottomSheetIfNeeded(animated: Bool) {
        guard baseBottomSheetViewController == nil,
              presentedViewController == nil,
              view.window != nil
        else { return }

        updateAnchorNow()

        let sheetVC = SheetViewController(rootView: AnyView(DefaultSearchView()))
        baseBottomSheetViewController = sheetVC

        sheetVC.sheetPresentationControllerContainerViewDidInit = { [weak self] controller in
            self?.updateContentSizeAndPosition(forSheetViewController: controller)
        }

        sheetVC.isModalInPresentation = true
        sheetVC.preferredContentSize = preferredSheetContentSize

        if let sheet = sheetVC.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: .init("small")) { [weak self] _ in
                    CGFloat(self?.smallDetentHeight ?? 130)
                },
                .medium(),
                .large()
            ]

            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
            sheet.sourceView = bottomSheetAnchorView
            sheet.largestUndimmedDetentIdentifier = .large
            sheet.delegate = self
        }

        present(sheetVC, animated: animated) { [weak self] in
            guard let self else { return }
            self.updateContentSizeAndPosition(forSheetViewController: sheetVC)
        }
    }

    // MARK: - Present Secondary Sheets (STACKING)
    private func presentViewControllerOnBaseSheetStack(_ viewController: UIViewController,
                                                       animated: Bool,
                                                       completion: (() -> Void)? = nil) {
        let presentHandler: (() -> Void) = { [weak self] in
            guard let self, let base = self.baseBottomSheetViewController else { return }

            var presenter: UIViewController = base
            while let next = presenter.presentedViewController {
                presenter = next
            }

            self.updateAnchorNow()

            presenter.present(viewController, animated: animated) { [weak self] in
                guard let self else { return }
                self.updateContentSizeAndPosition(forSheetViewController: viewController)
                completion?()
            }
        }

        if baseBottomSheetViewController != nil {
            presentHandler()
            return
        }

        presentBaseBottomSheetIfNeeded(animated: false)
        presentHandler()
    }

    // MARK: - Secondary Sheet Configuration
    private func configureSecondarySheet(_ vc: SheetViewController<AnyView>) {
        vc.isModalInPresentation = true
        vc.preferredContentSize = preferredSheetContentSize

        vc.sheetPresentationControllerContainerViewDidInit = { [weak self] controller in
            self?.updateContentSizeAndPosition(forSheetViewController: controller)
        }

        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.largestUndimmedDetentIdentifier = .large

            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
            sheet.sourceView = bottomSheetAnchorView
            sheet.delegate = self
        }
    }

    // MARK: - Subsheets
    private func presentCountrySheet(country: Country) {
        let host = SheetViewController(rootView: AnyView(
            CountryQuickActionPanelView(country: country, onClose: { [weak self] in
                self?.selectedCountry = nil
            })
        ))
        host.onDismiss = { [weak self] in self?.selectedCountry = nil }

        configureSecondarySheet(host)
        countrySheetVC = host
        presentViewControllerOnBaseSheetStack(host, animated: true)
    }

    private func presentAppearanceSheet() {
        let appearanceBinding = Binding<MapAppearance>(
            get: { self.appearance },
            set: { [weak self] newValue in self?.appearance = newValue }
        )

        let host = SheetViewController(rootView: AnyView(
            MapAppearancePanelView(appearance: appearanceBinding, onClose: { [weak self] in
                self?.showAppearancePanel = false
            })
        ))
        host.onDismiss = { [weak self] in self?.showAppearancePanel = false }

        configureSecondarySheet(host)
        appearanceSheetVC = host
        presentViewControllerOnBaseSheetStack(host, animated: true)
    }

    // MARK: - Sync
    private func syncStack() {
        if let country = selectedCountry, countrySheetVC == nil {
            presentCountrySheet(country: country)
        } else if selectedCountry == nil, let vc = countrySheetVC {
            vc.dismiss(animated: true)
            countrySheetVC = nil
        }

        if showAppearancePanel, appearanceSheetVC == nil {
            presentAppearanceSheet()
        } else if !showAppearancePanel, let vc = appearanceSheetVC {
            vc.dismiss(animated: true)
            appearanceSheetVC = nil
        }
    }

    // MARK: - Anchor View
    private func addBottomSheetAnchorView() {
        let anchorView = UIView()
        anchorView.translatesAutoresizingMaskIntoConstraints = false
        anchorView.backgroundColor = .clear
        anchorView.isUserInteractionEnabled = false

        view.addSubview(anchorView)

        NSLayoutConstraint.activate([
            anchorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            anchorView.widthAnchor.constraint(equalToConstant: 1),
            anchorView.heightAnchor.constraint(equalToConstant: 1)
        ])

        bottomSheetAnchorCenterXConstraint = anchorView.centerXAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leftAnchor,
            constant: bottomSheetAnchorCenterXConstant
        )
        bottomSheetAnchorCenterXConstraint.isActive = true

        self.bottomSheetAnchorView = anchorView
    }

    // MARK: - Map Host
    private func setupMap() {
        let host = UIHostingController(rootView: makeMapRootView())
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

    private func makeMapRootView() -> AnyView {
        let selectedCountryBinding = Binding<Country?>(
            get: { self.selectedCountry },
            set: { [weak self] newValue in self?.selectedCountry = newValue }
        )
        let showAppearanceBinding = Binding<Bool>(
            get: { self.showAppearancePanel },
            set: { [weak self] newValue in self?.showAppearancePanel = newValue }
        )
        let appearanceBinding = Binding<MapAppearance>(
            get: { self.appearance },
            set: { [weak self] newValue in self?.appearance = newValue }
        )

        return AnyView(
            MapView(
                path: path,
                selectedCountry: selectedCountryBinding,
                showAppearancePanel: showAppearanceBinding,
                appearance: appearanceBinding
            )
            .ignoresSafeArea()
        )
    }

    private func rebuildMapRoot() {
        mapHost.rootView = makeMapRootView()
    }
}

// MARK: - UISheetPresentationControllerDelegate
extension MapViewController: UISheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        updateSheetsContentSizeAndPosition()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === countrySheetVC {
            countrySheetVC = nil
            selectedCountry = nil
        } else if presentationController.presentedViewController === appearanceSheetVC {
            appearanceSheetVC = nil
            showAppearancePanel = false
        }
    }
}

// MARK: - Sheet Wrapper
final class SheetViewController<Content: View>: UIHostingController<Content> {
    var onDismiss: (() -> Void)?

    var sheetPresentationControllerContainerViewDidInit: ((UIViewController) -> Void)?
    private var didFireContainerInit = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !didFireContainerInit else { return }
        guard sheetPresentationController?.containerView != nil else { return }

        didFireContainerInit = true
        sheetPresentationControllerContainerViewDidInit?(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { onDismiss?() }
    }
}

// MARK: - Dismiss helper
extension UIViewController {
    func dismissPresentedViewControllerIfNecessary(animated: Bool = true, completion: (() -> ())? = nil) {
        guard let presentedViewController = self.presentedViewController,
              !presentedViewController.isBeingDismissed else {
            return
        }
        dismiss(animated: animated) { completion?() }
    }
}
