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
    
    func makeUIViewController(context: Context) -> MapViewController {
        let controller = MapViewController()
        controller.path = $path
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        uiViewController.path = $path
    }
}

// MARK: - MapViewController

final class MapViewController: UIViewController {
    
    // MARK: - State
    var path: Binding<NavigationPath>!
    private var selectedCountry: Country? { didSet { syncStack() } }
    private var showAppearancePanel: Bool = false { didSet { syncStack() } }
    private var appearance: MapAppearance = .twoD { didSet { rebuildMapRoot() } }
    
    // MARK: - UI
    private var mapHost: UIHostingController<AnyView>!
    
    // IMPORTANT: keep strong refs (like the original does)
    private var baseBottomSheetViewController: SheetViewController<AnyView>?
    private var countrySheetVC: UIViewController?
    private var appearanceSheetVC: UIViewController?
    
    // MARK: - Anchor (like original)
    private(set) var bottomSheetAnchorView: UIView!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!
    
    private let leftPadding: CGFloat = 0
    private let smallDetentHeight: CGFloat = 130
    
    private var didPresentInitialSheet = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        addBottomSheetAnchorView()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Match original behavior: keep sizes & anchor fresh during rotations/resizes
        updateSheetsContentSizeAndPosition()
        bottomSheetAnchorCenterXConstraint.constant = bottomSheetAnchorCenterXConstant
        
        // Present initial sheet only once, after first real layout pass (safeArea/bounds correct)
        if !didPresentInitialSheet {
            // Key: ensure anchor is already correct before presenting
            updateAnchorNow()
            
            presentBaseBottomSheetIfNeeded(animated: false) // original presents base without animation
            didPresentInitialSheet = true
        }
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
        if let base = baseBottomSheetViewController {
            updateContentSizeAndPosition(forSheetViewController: base)
            
            // Update the whole presented chain above base (stacking)
            var current = base.presentedViewController
            while let vc = current {
                updateContentSizeAndPosition(forSheetViewController: vc)
                current = vc.presentedViewController
            }
        }
    }
    
    /// Core positioning logic:
    /// - iOS17: always force container center/bounds (preferredContentSize was unreliable)
    /// - iOS18+: normally "do nothing" (sourceView should handle),
    ///           BUT: if UIKit resolved the container at the wrong width (common with deep stacked sheets on iOS26),
    ///           we apply the same fix as fallback WITHOUT animation.
    func updateContentSizeAndPosition(forSheetViewController viewController: UIViewController) {
        let preferredSize = preferredSheetContentSize
        viewController.preferredContentSize = preferredSize
        
        guard let containerView = viewController.sheetPresentationController?.containerView else { return }
        
        let forceLeftHalf: () -> Void = { [weak self] in
            guard let self else { return }
            
            let centerY = containerView.center.y
            var x = preferredSize.width / 2
            if !self.isSheetCentered {
                x += self.leftPadding
            }
            
            containerView.center = CGPoint(x: x, y: centerY)
            containerView.bounds = CGRect(origin: .zero, size: preferredSize)
            containerView.layoutIfNeeded()
        }
        
        if #available(iOS 18, *) {
            // "Native" path: let sourceView do it.
            // Fallback only if UIKit didn't apply preferred width (common with stacked sheets):
            let widthMismatch = abs(containerView.bounds.width - preferredSize.width) > 1.0
            
            if widthMismatch && !isSheetCentered {
                UIView.performWithoutAnimation {
                    forceLeftHalf()
                }
            }
            
            return
        }
        
        // iOS17: always force (but without animation to avoid morph)
        UIView.performWithoutAnimation {
            forceLeftHalf()
        }
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
        
        // iOS17 helper hook (original-style), iOS18+ will just no-op/fallback if needed
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
            // On iOS18+ this will normally do nothing; if UIKit chose wrong width, fallback fixes it.
            self.updateContentSizeAndPosition(forSheetViewController: sheetVC)
        }
    }
    
    // MARK: - Present Secondary Sheets (STACKING)
    
    private func presentViewControllerOnBaseSheetStack(_ viewController: UIViewController,
                                                       animated: Bool,
                                                       completion: (() -> Void)? = nil) {
        let presentHandler: (() -> Void) = { [weak self] in
            guard let self, let base = self.baseBottomSheetViewController else { return }
            
            // Find the topmost VC in the chain to stack above it
            var presenter: UIViewController = base
            while let next = presenter.presentedViewController {
                presenter = next
            }
            
            // CRITICAL: anchor must be correct BEFORE presenting
            self.updateAnchorNow()
            
            presenter.present(viewController, animated: animated) { [weak self] in
                guard let self else { return }
                // This call is safe on iOS18+: usually no-op, fallback only if needed.
                self.updateContentSizeAndPosition(forSheetViewController: viewController)
                
                // prevent "jumping"
                UIView.animate(withDuration: 0.1) {
                    self.view.layoutIfNeeded()
                }
                
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
    
    // MARK: - Secondary Sheet Configuration (match original flags)
    
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
    
    // MARK: - Anchor View (same structure as original)
    
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
