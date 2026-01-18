//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import UIKit
import SwiftUI
import SwiftData
import Combine

final class SheetStackStateModel: ObservableObject {
    @Published var baseDetentIdentifier: UISheetPresentationController.Detent.Identifier?
    @Published var hasStoredBaseDetent: Bool = false
    @Published var isCountrySheetPresented: Bool = false
    @Published var isAppearanceSheetPresented: Bool = false
}

// MARK: - SwiftUI Bridge

struct MapControllerRepresentable: UIViewControllerRepresentable {
    
    @Binding var path: NavigationPath
    
    @Environment(\.modelContext) private var modelContext

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MapViewController {
        let controller = MapViewController(modelContext: modelContext)
        controller.path = $path
        return controller
    }

    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        uiViewController.path = $path
        context.coordinator.handlePathUpdate(path, controller: uiViewController)
    }

    final class Coordinator {
        private var lastCount: Int?

        func handlePathUpdate(_ path: NavigationPath, controller: MapViewController) {
            let newCount = path.count
            defer { lastCount = newCount }

            guard let old = lastCount else { return }

            // Pop to root => kill sheets immediately (before VC detaches)
            if newCount == 0, old > 0 {
                controller.dismissSheetsImmediatelyForExit()
            }
        }
    }
}

// MARK: - MapViewController

final class MapViewController: UIViewController, UINavigationControllerDelegate {

    // Designated initializer to provide required dependencies
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        // Interface Builder is not used; provide a default fatalError to catch accidental init
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State
    var path: Binding<NavigationPath>!

    private var selectedCountry: Country? {
        didSet {
            syncStack()
            rebuildMapRoot()
        }
    }

    private var showAppearancePanel: Bool = false { didSet { syncStack() } }
    private var appearance: MapAppearance = .twoD { didSet { rebuildMapRoot() } }
    private var filter: CountryStatusFilter = .all { didSet { rebuildMapRoot() } }
    
    private let sheetState = SheetStackStateModel()

    // MARK: - UI
    private var mapHost: UIHostingController<AnyView>!

    // Keep strong refs
    private var baseBottomSheetViewController: SheetViewController<AnyView>?
    private var countrySheetVC: UIViewController?
    private var appearanceSheetVC: UIViewController?
    
    var modelContext: ModelContext
    
    // Stack Logic: Merkt sich die Größe des Base Sheets, bevor es minimiert wird
    private var storedBaseDetent: UISheetPresentationController.Detent.Identifier?

    // MARK: - Anchor
    private(set) var bottomSheetAnchorView: UIView!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!

    private let leftPadding: CGFloat = 0

    private var didPresentInitialSheet = false
    private var isSwappingSheets = false

    /// Flag: Default/Base-Sheet nur im Landscape sichtbar
    var showsDefaultSheetOnlyInLandscape: Bool = true

    // timing
    private var initialPresentWorkItem: DispatchWorkItem?
    private let initialSheetDelay: TimeInterval = 0.0

    // nav hooks
    private weak var previousNavDelegate: UINavigationControllerDelegate?
    private var popGestureAttached = false

    // rotation guards
    private var isInSizeTransition = false
    private var isExiting = false

    private var canPresentNow: Bool {
        guard !isExiting, isViewLoaded, view.window != nil else { return false }
        return true
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        addBottomSheetAnchorView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isExiting = false

        attachNavigationEarlyDismissHooks()

        reconcileDefaultSheetVisibility()

        if shouldShowDefaultSheet() {
            scheduleInitialSheetPresentationIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isExiting = true
        dismissSheetsImmediatelyForExit()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        detachNavigationEarlyDismissHooks()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let shouldShowBaseAfter = shouldShowDefaultSheet(for: size)
        isInSizeTransition = true

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }

            // During transition: only "soft" changes
            self.bottomSheetAnchorCenterXConstraint.constant = self.bottomSheetAnchorCenterXConstant
            self.updateSheetsContentSizeAndPosition()
            self.layoutVisibleSheetNavigationBars(hard: false)

            // Base: only fade (no dismiss/present during transition)
            self.setBaseSheetHidden(!shouldShowBaseAfter, animated: true)

        }, completion: { [weak self] _ in
            guard let self else { return }

            self.isInSizeTransition = false

            // Final: one hard stabilize
            self.bottomSheetAnchorCenterXConstraint.constant = self.bottomSheetAnchorCenterXConstant
            self.updateSheetsContentSizeAndPosition()
            self.layoutVisibleSheetNavigationBars(hard: true)

            // Now it is safe to do real dismiss/present decisions
            self.reconcileDefaultSheetVisibility(for: size)
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        updateSheetsContentSizeAndPosition()
    }

    // MARK: - Orientation policy

    private var isLandscapeNow: Bool { view.bounds.width > view.bounds.height }

    private func shouldShowDefaultSheet(for size: CGSize? = nil) -> Bool {
        guard showsDefaultSheetOnlyInLandscape else { return true }
        if let size { return size.width > size.height }
        return isLandscapeNow
    }

    /// Fade the *whole* base sheet container (removes "ghost" glass & shadow).
    private func setBaseSheetHidden(_ hidden: Bool, animated: Bool) {
        guard let base = baseBottomSheetViewController else { return }
        guard let container = base.presentationController?.containerView else { return }

        let apply = {
            container.alpha = hidden ? 0.0 : 1.0
            container.isUserInteractionEnabled = !hidden
            container.accessibilityElementsHidden = hidden
        }

        if animated {
            // inside transition coordinator this will be synced nicely
            apply()
        } else {
            UIView.performWithoutAnimation { apply() }
        }
    }

    /// Real show/hide/dismiss logic.
    /// - During transition: do *nothing* but fade (handled above).
    private func reconcileDefaultSheetVisibility(for size: CGSize? = nil) {
        if isInSizeTransition {
            let shouldShow = shouldShowDefaultSheet(for: size)
            setBaseSheetHidden(!shouldShow, animated: true)
            return
        }

        let shouldShow = shouldShowDefaultSheet(for: size)

        if shouldShow {
            // Ensure base exists
            if baseBottomSheetViewController == nil {
                guard canPresentNow else { return }
                presentBaseBottomSheetIfNeeded(animated: true, completion: nil)
                didPresentInitialSheet = true
            }
            setBaseSheetHidden(false, animated: false)
            return
        }

        // should NOT show base (portrait policy)
        guard let base = baseBottomSheetViewController else { return }

        let hasSubsheetsAbove = (base.presentedViewController != nil)
        let wantsAnySheet = (selectedCountry != nil) || showAppearancePanel

        if hasSubsheetsAbove || wantsAnySheet {
            // keep chain alive, just hide base visuals
            setBaseSheetHidden(true, animated: false)
        } else {
            // base alone -> dismiss for real
            base.dismiss(animated: false)
            baseBottomSheetViewController = nil
            didPresentInitialSheet = false
        }
    }

    // MARK: - Early dismiss hooks

    private func attachNavigationEarlyDismissHooks() {
        guard let nav = navigationController else { return }

        if previousNavDelegate == nil { previousNavDelegate = nav.delegate }
        nav.delegate = self

        if let popGesture = nav.interactivePopGestureRecognizer, !popGestureAttached {
            popGesture.addTarget(self, action: #selector(handleInteractivePop(_:)))
            popGestureAttached = true
        }
    }

    private func detachNavigationEarlyDismissHooks() {
        if let nav = navigationController {
            if nav.delegate === self { nav.delegate = previousNavDelegate }
        }

        if let popGesture = navigationController?.interactivePopGestureRecognizer, popGestureAttached {
            popGesture.removeTarget(self, action: #selector(handleInteractivePop(_:)))
            popGestureAttached = false
        }

        previousNavDelegate = nil
    }

    @objc private func handleInteractivePop(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .began else { return }
        dismissSheetsImmediatelyForExit()
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        if viewController !== self {
            dismissSheetsImmediatelyForExit()
        }
        previousNavDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        previousNavDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
    }

    // MARK: - Initial present

    private func scheduleInitialSheetPresentationIfNeeded() {
        guard shouldShowDefaultSheet() else { return }
        guard !didPresentInitialSheet else { return }
        guard canPresentNow else { return }

        initialPresentWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.canPresentNow else { return }
            guard !self.didPresentInitialSheet else { return }

            self.updateAnchorNow()
            self.presentBaseBottomSheetIfNeeded(animated: true, completion: nil)
            self.didPresentInitialSheet = true
        }
        initialPresentWorkItem = work

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
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Immediate dismiss (EXIT)

    func dismissSheetsImmediatelyForExit() {
        initialPresentWorkItem?.cancel()
        initialPresentWorkItem = nil

        if presentedViewController != nil {
            dismiss(animated: false)
        }

        baseBottomSheetViewController = nil
        countrySheetVC = nil
        appearanceSheetVC = nil

        didPresentInitialSheet = false
        isSwappingSheets = false
        selectedCountry = nil
        showAppearancePanel = false
        storedBaseDetent = nil
        
        updateSheetState()
    }
    
    // MARK: - Sheet State Update Helper
    
    private func updateSheetState() {
        sheetState.baseDetentIdentifier = baseBottomSheetViewController?.sheetPresentationController?.selectedDetentIdentifier
        sheetState.hasStoredBaseDetent = (storedBaseDetent != nil)
        sheetState.isCountrySheetPresented = (countrySheetVC != nil)
        sheetState.isAppearanceSheetPresented = (appearanceSheetVC != nil)
    }

    // MARK: - Preferred size

    private var isSheetCentered: Bool {
        traitCollection.horizontalSizeClass == .compact &&
        traitCollection.verticalSizeClass == .regular
    }

    var preferredSheetContentSize: CGSize {
        let width = isSheetCentered
            ? view.bounds.width
            : (view.bounds.width - view.safeAreaInsets.left) * 0.4
        return .init(width: width, height: view.bounds.height)
    }

    var bottomSheetAnchorCenterXConstant: CGFloat {
        preferredSheetContentSize.width * 0.5 + leftPadding
    }

    private func updateAnchorNow() {
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        view.layoutIfNeeded()
    }

    // MARK: - Update sheet sizes (stack)

    private func updateSheetsContentSizeAndPosition() {
        guard let base = baseBottomSheetViewController else { return }

        updateContentSizeAndPosition(forSheetViewController: base)

        var current = base.presentedViewController
        while let vc = current {
            updateContentSizeAndPosition(forSheetViewController: vc)
            current = vc.presentedViewController
        }
    }

    func updateContentSizeAndPosition(forSheetViewController viewController: UIViewController) {
        let preferredSize = preferredSheetContentSize
        viewController.preferredContentSize = preferredSize

        guard let containerView = viewController.sheetPresentationController?.containerView else { return }

        // During rotation UIKit sometimes reports 0-width containers (drop shadow warnings).
        if isInSizeTransition, containerView.bounds.width <= 1 { return }

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

            // during transition: soft only
            if self.isInSizeTransition {
                containerView.setNeedsLayout()
            } else {
                containerView.layoutIfNeeded()
            }
        }

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
    }
    
    // MARK: - Base Bottom Sheet

    private func presentBaseBottomSheetIfNeeded(animated: Bool, completion: (() -> Void)?) {
        guard canPresentNow else { return }
        guard baseBottomSheetViewController == nil,
              presentedViewController == nil
        else { return }

        updateAnchorNow()

        let selectedCountryBinding = Binding<Country?>(
            get: { [weak self] in self?.selectedCountry },
            set: { [weak self] in self?.selectedCountry = $0 }
        )
        
        let filterBinding = Binding<CountryStatusFilter>(
            get: { [weak self] in self?.filter ?? .all },
            set: { [weak self] in self?.filter = $0 }
        )

        let rootView = AnyView(
            DefaultSearchView(selectedCountry: selectedCountryBinding, filter: filterBinding, sheetState: sheetState)
                .environment(\.modelContext, modelContext)
        )
        
        let sheetVC = SheetViewController(rootView: rootView)
        baseBottomSheetViewController = sheetVC

        sheetVC.sheetPresentationControllerContainerViewDidInit = { [weak self] controller in
            guard let self else { return }
            self.updateContentSizeAndPosition(forSheetViewController: controller)
            self.setBaseSheetHidden(!self.shouldShowDefaultSheet(), animated: false)
        }

        sheetVC.isModalInPresentation = true
        sheetVC.preferredContentSize = preferredSheetContentSize

        if let sheet = sheetVC.sheetPresentationController {
            sheet.detents = [
                .custom(identifier: .init("small")) { _ in CGFloat(85) },
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
            self.setBaseSheetHidden(!self.shouldShowDefaultSheet(), animated: false)
            self.updateSheetState()
            completion?()
        }
    }

    // MARK: - Present Secondary Sheets (STACKING)

    private func presentViewControllerOnBaseSheetStack(_ viewController: UIViewController,
                                                       animated: Bool,
                                                       completion: (() -> Void)? = nil) {
        guard canPresentNow else { return }

        let doPresent: () -> Void = { [weak self] in
            guard let self, let base = self.baseBottomSheetViewController else { return }

            var presenter: UIViewController = base
            while let next = presenter.presentedViewController, !next.isBeingDismissed {
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
            doPresent()
            return
        }

        // Create base as hidden root if needed (portrait case)
        presentBaseBottomSheetIfNeeded(animated: true) { [weak self] in
            guard let self else { return }
            self.didPresentInitialSheet = true
            self.setBaseSheetHidden(!self.shouldShowDefaultSheet(), animated: false)
            doPresent()
        }
    }

    // MARK: - Navigation Sheet

    private func presentNavigationSheet(rootView: AnyView,
                                        title: String,
                                        detents: [UISheetPresentationController.Detent],
                                        prefersGrabberVisible: Bool = true,
                                        largestUndimmedDetentIdentifier: UISheetPresentationController.Detent.Identifier = .large,
                                        onClose: @escaping () -> Void) -> UINavigationController {
        let host = SheetViewController(rootView: rootView)
        host.navigationItem.title = title
        host.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { _ in onClose() }
        )

        let nav = SheetNavigationController(rootViewController: host)
        nav.preferredContentSize = preferredSheetContentSize

        nav.sheetPresentationControllerContainerViewDidInit = { [weak self] controller in
            self?.updateContentSizeAndPosition(forSheetViewController: controller)
        }

        if let sheet = nav.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = prefersGrabberVisible
            sheet.largestUndimmedDetentIdentifier = largestUndimmedDetentIdentifier

            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true

            sheet.sourceView = bottomSheetAnchorView
            sheet.delegate = self
        }

        presentViewControllerOnBaseSheetStack(nav, animated: true)
        return nav
    }

    // MARK: - Subsheets

    private func presentCountrySheet(country: Country) {
        let contentView = AnyView(
            CountryQuickActionPanelView(country: country, onClose: { [weak self] in
                self?.selectedCountry = nil
            })
        )

        countrySheetVC = presentNavigationSheet(
            rootView: contentView,
            title: country.nameEnglish,
            detents: [
                .custom(identifier: .init("small")) { _ in CGFloat(210) }
            ],
            prefersGrabberVisible: false,
            largestUndimmedDetentIdentifier: .init(rawValue: "small")
        ) { [weak self] in
            self?.selectedCountry = nil
            self?.updateSheetState()
        }
        updateSheetState()
    }

    private func presentAppearanceSheet() {
        let appearanceBinding = Binding<MapAppearance>(
            get: { self.appearance },
            set: { [weak self] newValue in self?.appearance = newValue }
        )

        let contentView = AnyView(MapAppearancePanelView(appearance: appearanceBinding))

        appearanceSheetVC = presentNavigationSheet(
            rootView: contentView,
            title: "Appearance",
            detents: [
                .custom(identifier: .init("small")) { _ in CGFloat(130) }
            ],
            prefersGrabberVisible: false,
            largestUndimmedDetentIdentifier: .init(rawValue: "small")
        ) { [weak self] in
            self?.showAppearancePanel = false
            self?.updateSheetState()
        }
        updateSheetState()
    }

    // MARK: - Sync (present / update / dismiss)

    private func syncStack() {
        if isSwappingSheets { return }

        // --- Logic: Stack Overlays ---
        let isShowingSecondary = (selectedCountry != nil) || showAppearancePanel
        
        // ANIMATION BASE SHEET:
        // Wenn Stack (Overlay) aktiv: Base Sheet auf "small" (85pt) minimieren.
        // Wenn Stack inaktiv: Base Sheet wieder hochfahren auf den letzten gespeicherten Detent.
        if let baseSheet = baseBottomSheetViewController?.sheetPresentationController {
            
            if isShowingSecondary {
                // Wir speichern den aktuellen Detent nur, wenn wir ihn nicht schon gespeichert haben.
                // Grund: Wenn man von Country A -> Country B wechselt, bleibt isShowingSecondary true.
                // Wir wollen aber nicht den Status "small" speichern, sondern den Status, bevor IRGENDWAS aufging.
                if storedBaseDetent == nil {
                    // Default fallback: .medium wenn nichts gesetzt war
                    storedBaseDetent = baseSheet.selectedDetentIdentifier ?? .medium
                    updateSheetState()
                }
                
                // Animiere auf small
                baseSheet.animateChanges {
                    baseSheet.selectedDetentIdentifier = .init("small")
                }
            } else {
                // Stack ist weg -> Restore
                if let restoreDetent = storedBaseDetent {
                    baseSheet.animateChanges {
                        baseSheet.selectedDetentIdentifier = restoreDetent
                    }
                    // Reset, damit beim nächsten Mal wieder neu gespeichert wird
                    storedBaseDetent = nil
                    updateSheetState()
                }
            }
        }

        // --- Logic: Secondary Sheets Presentation ---

        // if Appearance open and now a country is selected -> dismiss appearance first then show/update country
        if let country = selectedCountry, let appearanceVC = appearanceSheetVC {
            isSwappingSheets = true
            showAppearancePanel = false

            if countrySheetVC != nil {
                updateCountrySheet(country: country) // update immediately to avoid "old country flash"
            }

            appearanceVC.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.appearanceSheetVC = nil
                self.isSwappingSheets = false

                if self.countrySheetVC == nil {
                    self.presentCountrySheet(country: country)
                } else {
                    self.updateCountrySheet(country: country)
                }

                self.reconcileDefaultSheetVisibility()
            }
            return
        }

        // Country: present/update/dismiss
        if let country = selectedCountry {
            if countrySheetVC == nil {
                presentCountrySheet(country: country)
            } else {
                updateCountrySheet(country: country)
            }
        } else if let vc = countrySheetVC {
            vc.dismiss(animated: true)
            countrySheetVC = nil
        }

        // Appearance: present/dismiss
        if showAppearancePanel {
            if appearanceSheetVC == nil {
                presentAppearanceSheet()
            }
        } else if let vc = appearanceSheetVC {
            vc.dismiss(animated: true)
            appearanceSheetVC = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.reconcileDefaultSheetVisibility()
        }
    }

    private func updateCountrySheet(country: Country) {
        guard let nav = countrySheetVC as? UINavigationController,
              let host = nav.viewControllers.first as? SheetViewController<AnyView>
        else { return }

        host.navigationItem.title = country.nameEnglish
        host.rootView = AnyView(
            CountryQuickActionPanelView(country: country, onClose: { [weak self] in
                self?.selectedCountry = nil
            })
        )
    }

    // MARK: - NavBar “jump” helper

    private func layoutVisibleSheetNavigationBars(hard: Bool) {
        func layoutNav(_ vc: UIViewController?) {
            guard let nav = vc as? UINavigationController else { return }
            nav.navigationBar.setNeedsLayout()
            nav.view.setNeedsLayout()
            if hard {
                nav.navigationBar.layoutIfNeeded()
                nav.view.layoutIfNeeded()
            }
        }
        layoutNav(countrySheetVC)
        layoutNav(appearanceSheetVC)
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
            get: { [weak self] in self?.selectedCountry },
            set: { [weak self] in self?.selectedCountry = $0 }
        )

        let showAppearanceBinding = Binding<Bool>(
            get: { self.showAppearancePanel },
            set: { [weak self] in self?.showAppearancePanel = $0 }
        )

        let appearanceBinding = Binding<MapAppearance>(
            get: { self.appearance },
            set: { [weak self] in self?.appearance = $0 }
        )
        
        let filterBinding = Binding<CountryStatusFilter>(
            get: { self.filter },
            set: { [weak self] in self?.filter = $0 }
        )

        return AnyView(
            MapView(
                path: path,
                selectedCountry: selectedCountryBinding,
                showAppearancePanel: showAppearanceBinding,
                appearance: appearanceBinding,
                filter: filterBinding
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
        
        // Wenn der User am Base Sheet zieht, während KEIN Stack oben drauf ist,
        // merken wir uns das für später (falls wir storedBaseDetent aktualisieren müssen).
        // Wir dürfen es NICHT updaten, wenn ein Stack drauf ist, da wir das Base Sheet ja gerade zwangsweise
        // auf "small" gezwungen haben. Das soll nicht als Präferenz des Users gespeichert werden.
        let isSecondarySheetPresented = (countrySheetVC != nil || appearanceSheetVC != nil)
        
        if sheetPresentationController.presentedViewController === baseBottomSheetViewController {
            if !isSecondarySheetPresented {
                // User interacting with base sheet freely -> Update internal logic if needed,
                // but strictly `storedBaseDetent` is mainly for restore logic.
                // However, if we wanted to be super precise, we could track last known state here.
            }
        }
        
        updateSheetsContentSizeAndPosition()
        updateSheetState()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === countrySheetVC {
            countrySheetVC = nil
            selectedCountry = nil
        } else if presentationController.presentedViewController === appearanceSheetVC {
            appearanceSheetVC = nil
            showAppearancePanel = false
        } else if presentationController.presentedViewController === baseBottomSheetViewController {
            baseBottomSheetViewController = nil
            didPresentInitialSheet = false
        }

        reconcileDefaultSheetVisibility()
        updateSheetState()
    }
}

// MARK: - SheetNavigationController

final class SheetNavigationController: UINavigationController {
    var sheetPresentationControllerContainerViewDidInit: ((UIViewController) -> Void)?
    private var didFireContainerInit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard !didFireContainerInit else { return }
        guard sheetPresentationController?.containerView != nil else { return }

        didFireContainerInit = true
        sheetPresentationControllerContainerViewDidInit?(self)
    }
}

// MARK: - Sheet Wrapper

final class SheetViewController<Content: View>: UIHostingController<Content> {
    var onDismiss: (() -> Void)?

    var sheetPresentationControllerContainerViewDidInit: ((UIViewController) -> Void)?
    private var didFireContainerInit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

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

