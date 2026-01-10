//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import UIKit
import SwiftUI

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

final class MapViewController: UIViewController {

    // MARK: State
    var path: Binding<NavigationPath>!

    private var selectedCountry: Country? { didSet { syncStack(animated: true) } }
    private var showAppearancePanel: Bool = false { didSet { syncStack(animated: true) } }
    private var appearance: MapAppearance = .twoD { didSet { rebuildMapRoot() } }

    // MARK: UI
    private var mapHost: UIHostingController<AnyView>!
    private var sheetHost: UIHostingController<AnyView>?

    // MARK: Anchor / geometry
    private let bottomSheetAnchorView = UIView()
    private var bottomSheetAnchorWidthConstraint: NSLayoutConstraint!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!

    private var didPresentInitialSheet = false

    // MARK: Stack (inside the single sheet)
    private enum PanelLevel: Equatable {
        case search
        case country(Country)
        case appearance
    }
    private var panelStack: [PanelLevel] = [.search]

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupMap()
        setupBottomSheetAnchorView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didPresentInitialSheet {
            view.layoutIfNeeded()
            presentBaseSheet(animated: false)
            didPresentInitialSheet = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSizeAndPosition()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateContentSizeAndPosition()
            self.sheetHost?.sheetPresentationController?.invalidateDetents()
        })
    }

    // MARK: Detents
    private var collapsedDetent: UISheetPresentationController.Detent {
        .custom(identifier: .init("collapsed")) { _ in 130 }
    }

    // MARK: Present
    private func presentBaseSheet(animated: Bool) {
        let host = UIHostingController(rootView: currentPanelView())
        host.modalPresentationStyle = .pageSheet

        if #available(iOS 18.0, *) {
            host.sizingOptions = [.preferredContentSize]
        }

        let w = preferredWidth()
        host.preferredContentSize = CGSize(width: w, height: 0)

        if let sheet = host.sheetPresentationController {
            sheet.sourceView = bottomSheetAnchorView
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true

            sheet.detents = [collapsedDetent, .medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false

            sheet.selectedDetentIdentifier = collapsedDetent.identifier
            sheet.largestUndimmedDetentIdentifier = .large
        }

        sheetHost = host

        present(host, animated: animated) {
            self.updateContentSizeAndPosition()
            DispatchQueue.main.async { self.updateContentSizeAndPosition() }
        }
    }

    // MARK: Stack sync
    private func syncStack(animated: Bool) {
        // Build desired stack from state (like your old chain logic)
        var desired: [PanelLevel] = [.search]
        if let c = selectedCountry { desired.append(.country(c)) }
        if showAppearancePanel { desired.append(.appearance) }

        panelStack = desired
        updateSheetContent(animated: animated)
    }

    private func updateSheetContent(animated: Bool) {
        guard let host = sheetHost else { return }

        let newView = currentPanelView()
        if animated {
            UIView.transition(with: host.view, duration: 0.20, options: [.transitionCrossDissolve]) {
                host.rootView = newView
            }
        } else {
            host.rootView = newView
        }

        updateContentSizeAndPosition()
    }

    // MARK: View resolution from stack top
    private func currentPanelView() -> AnyView {
        guard let top = panelStack.last else { return AnyView(DefaultSearchView()) }

        switch top {
        case .search:
            return AnyView(DefaultSearchView())

        case .country(let country):
            return AnyView(
                CountryQuickActionPanelView(
                    country: country,
                    onClose: { self.selectedCountry = nil }
                )
            )

        case .appearance:
            return AnyView(
                MapAppearancePanelView(
                    appearance: Binding(get: { self.appearance }, set: { self.appearance = $0 }),
                    onClose: { self.showAppearancePanel = false }
                )
            )
        }
    }

    // MARK: Geometry
    private func preferredWidth() -> CGFloat {
        let isLandscape = view.bounds.width > view.bounds.height
        let safeInsets = view.safeAreaInsets
        let safeWidth = view.bounds.width - safeInsets.left - safeInsets.right
        return isLandscape ? safeWidth * 0.5 : safeWidth
    }

    private func updateContentSizeAndPosition() {
        let isLandscape = view.bounds.width > view.bounds.height
        let safeInsets = view.safeAreaInsets
        let w = preferredWidth()

        bottomSheetAnchorWidthConstraint.constant = w
        bottomSheetAnchorCenterXConstraint.constant = w * 0.5

        guard let host = sheetHost else { return }
        host.preferredContentSize = CGSize(width: w, height: 0)

        if let container = host.presentationController?.containerView {
            if isLandscape {
                container.frame.size.width = w
                container.frame.origin.x = safeInsets.left
                container.bounds = CGRect(origin: .zero, size: container.frame.size)
                container.layoutIfNeeded()
            } else {
                container.frame = view.bounds
                container.layoutIfNeeded()
            }
        }

        host.view.superview?.backgroundColor = .clear
    }

    // MARK: Anchor setup
    private func setupBottomSheetAnchorView() {
        bottomSheetAnchorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSheetAnchorView.isUserInteractionEnabled = false
        bottomSheetAnchorView.backgroundColor = .clear
        view.addSubview(bottomSheetAnchorView)

        bottomSheetAnchorWidthConstraint = bottomSheetAnchorView.widthAnchor.constraint(equalToConstant: 1)
        bottomSheetAnchorCenterXConstraint = bottomSheetAnchorView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)

        NSLayoutConstraint.activate([
            bottomSheetAnchorView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bottomSheetAnchorView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomSheetAnchorView.heightAnchor.constraint(equalToConstant: 1),
            bottomSheetAnchorWidthConstraint,
            bottomSheetAnchorCenterXConstraint
        ])
    }

    // MARK: Map
    private func setupMap() {
        let host = UIHostingController(rootView: makeMapRootView())
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        mapHost = host
    }

    private func makeMapRootView() -> AnyView {
        AnyView(
            MapView(
                path: path,
                selectedCountry: Binding(get: { self.selectedCountry }, set: { self.selectedCountry = $0 }),
                showAppearancePanel: Binding(get: { self.showAppearancePanel }, set: { self.showAppearancePanel = $0 }),
                appearance: Binding(get: { self.appearance }, set: { self.appearance = $0 })
            ).ignoresSafeArea()
        )
    }

    private func rebuildMapRoot() {
        mapHost.rootView = makeMapRootView()
    }
}
