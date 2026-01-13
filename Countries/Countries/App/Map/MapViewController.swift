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
        context.coordinator.handlePathUpdate(path, controller: uiViewController)
    }
    
    final class Coordinator {
        private var lastCount: Int?
        
        func handlePathUpdate(_ path: NavigationPath, controller: MapViewController) {
            let newCount = path.count
            defer { lastCount = newCount }
            
            guard let old = lastCount else { return }
            
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
    private var selectedCountry: Country? {
        didSet {
            syncStack()
            rebuildMapRoot()
        }
    }
    private var showAppearancePanel: Bool = false { didSet { syncStack() } }
    private var appearance: MapAppearance = .twoD { didSet { rebuildMapRoot() } }
    
    // MARK: - UI
    private var mapHost: UIHostingController<AnyView>!
    
    private var baseBottomSheetViewController: SheetViewController<AnyView>?
    private var countrySheetVC: UIViewController?
    private var appearanceSheetVC: UIViewController?
    
    // MARK: - Anchor
    private(set) var bottomSheetAnchorView: UIView!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!
    
    private let leftPadding: CGFloat = 0
    private let smallDetentHeight: CGFloat = 130
    
    private var didPresentInitialSheet = false
    private var isSwappingSheets = false
    
    // initial present timing
    private var initialPresentWorkItem: DispatchWorkItem?
    private let initialSheetDelay: TimeInterval = 0.0
    
    // nav hooks
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
        
        attachNavigationEarlyDismissHooks()
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
        
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        updateSheetsContentSizeAndPosition()
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
        guard !didPresentInitialSheet else { return }
        guard view.window != nil else { return }
        
        initialPresentWorkItem?.cancel()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.didPresentInitialSheet else { return }
            guard self.view.window != nil else { return }
            
            self.updateAnchorNow()
            
            self.presentBaseBottomSheetIfNeeded(animated: true)
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
    
    // MARK: - Immediate dismiss
    
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
        selectedCountry = nil
        showAppearancePanel = false
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
    
    // MARK: - Update sheet sizes
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
    
    // Shared helper: apply to an explicit containerView
    private func applySheetFrame(containerView: UIView, preferredSize: CGSize) {
        let desiredCenterX: CGFloat = {
            if isSheetCentered {
                return view.bounds.midX
            } else {
                return view.safeAreaInsets.left + leftPadding + preferredSize.width * 0.5
            }
        }()
        
        let centerY = containerView.center.y
        containerView.center = CGPoint(x: desiredCenterX, y: centerY)
        containerView.bounds = CGRect(origin: .zero, size: preferredSize)
        containerView.layoutIfNeeded()
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
    
    // MARK: - Navigation Sheet (with early container fix)
    
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
        
        // Hook: as soon as container exists -> apply fix
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
                .custom(identifier: .init("small")) { _ in CGFloat(210) },
                .medium(),
                .large()
            ]
        ) { [weak self] in
            self?.selectedCountry = nil
        }
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
        }
    }
    
    // MARK: - Sync
    
    private func syncStack() {
        if isSwappingSheets { return }
        
        // Special case: Appearance ist offen und jetzt wird ein Land selektiert
        if let country = selectedCountry, let appearanceVC = appearanceSheetVC {
            isSwappingSheets = true
            showAppearancePanel = false
            
            if countrySheetVC != nil {
                self.updateCountrySheet(country: country)
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
            }
            return
        }
        
        // Country normal (present / update / dismiss)
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
        
        // Appearance normal (present / dismiss)
        if showAppearancePanel {
            if appearanceSheetVC == nil {
                presentAppearanceSheet()
            }
        } else if let vc = appearanceSheetVC {
            vc.dismiss(animated: true)
            appearanceSheetVC = nil
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

// MARK: - SheetNavigationController

final class SheetNavigationController: UINavigationController {
    
    var sheetPresentationControllerContainerViewDidInit: ((UIViewController) -> Void)?
    private var didFireContainerInit = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // make container transparent (works because THIS controller is presented)
        if let container = sheetPresentationController?.containerView {
            container.backgroundColor = .clear
            container.subviews.first?.backgroundColor = .clear
        }
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
