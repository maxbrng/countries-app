//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import UIKit
import SwiftUI

// MARK: - SwiftUI Bridge
struct MapControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MapViewController {
        MapViewController()
    }
    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {}
}

// MARK: - MapViewController
final class MapViewController: UIViewController {

    // MARK: - State
    private var selectedCountry: Country? {
        didSet { updatePanelPresentation(animated: true) }
    }

    private var showAppearancePanel: Bool = false {
        didSet { updatePanelPresentation(animated: true) }
    }

    private var appearance: MapAppearance = .twoD {
        didSet { rebuildMapRoot() }
    }

    // MARK: - UI Elements
    private var mapHost: UIHostingController<AnyView>!
    private var sheetPanelHost: UIHostingController<AnyView>?
    
    // Das Herzstück für die Positionierung
    private let bottomSheetAnchorView = UIView()
    private var bottomSheetAnchorWidthConstraint: NSLayoutConstraint!
    private var bottomSheetAnchorCenterXConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupMap()
        setupBottomSheetAnchorView()
        updateContentSizeAndPosition()
        updatePanelPresentation(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Wichtig: Hier wird bei jeder Frame-Änderung (Rotation) nachjustiert
        updateContentSizeAndPosition()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            self.updateContentSizeAndPosition()
            // Erzwingt das Layout-Update des Sheets während der Rotation
            if let sheet = self.sheetPanelHost?.sheetPresentationController {
                sheet.invalidateDetents()
            }
        })
    }

    // MARK: - Setup Map
    private func setupMap() {
        let root = makeMapRootView()
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        // Map ist immer Fullscreen und ignoriert SafeAreas (via SwiftUI)
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
        let v = MapView(
            selectedCountry: Binding(get: { self.selectedCountry }, set: { self.selectedCountry = $0 }),
            showAppearancePanel: Binding(get: { self.showAppearancePanel }, set: { self.showAppearancePanel = $0 }),
            appearance: Binding(get: { self.appearance }, set: { self.appearance = $0 })
        )
        .ignoresSafeArea() // Verhindert weiße Ränder oben/unten
        return AnyView(v)
    }

    private func rebuildMapRoot() {
        mapHost.rootView = makeMapRootView()
    }

    // MARK: - BottomSheet Anchor Logic
    private func setupBottomSheetAnchorView() {
        bottomSheetAnchorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSheetAnchorView.isUserInteractionEnabled = false
        bottomSheetAnchorView.backgroundColor = .clear
        view.addSubview(bottomSheetAnchorView)

        // Der Anker klebt links unten am Safe Area
        let leading = bottomSheetAnchorView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        let bottom = bottomSheetAnchorView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        let height = bottomSheetAnchorView.heightAnchor.constraint(equalToConstant: 1)
        
        // Diese Constraints steuern die Breite und Position des Panels
        bottomSheetAnchorWidthConstraint = bottomSheetAnchorView.widthAnchor.constraint(equalToConstant: 1)
        bottomSheetAnchorCenterXConstraint = bottomSheetAnchorView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        
        NSLayoutConstraint.activate([leading, bottom, height, bottomSheetAnchorWidthConstraint, bottomSheetAnchorCenterXConstraint])
    }

    private func updateContentSizeAndPosition() {
        let isLandscape = view.bounds.width > view.bounds.height
        let safeInsets = view.safeAreaInsets
        
        let preferredWidth: CGFloat
        if isLandscape {
            // Exakt 50% der Screenbreite im Landscape
            preferredWidth = (view.bounds.width - safeInsets.left) * 0.5
        } else {
            // Volle Breite im Portrait
            preferredWidth = view.bounds.width - (safeInsets.left + safeInsets.right)
        }

        // Wir machen den unsichtbaren Anker exakt so breit wie das gewünschte Sheet
        bottomSheetAnchorWidthConstraint.constant = preferredWidth
        // Wir verschieben den Mittelpunkt des Ankers, damit das System weiß, wo die Mitte des Sheets ist
        bottomSheetAnchorCenterXConstraint.constant = preferredWidth * 0.5

        if let host = sheetPanelHost {
            host.preferredContentSize = CGSize(width: preferredWidth, height: 0)
            
            // Harder Override für den Container-Frame (Zwingt iOS 26 zur Sidebar)
            if let container = host.presentationController?.containerView {
                if isLandscape {
                    container.frame.size.width = preferredWidth
                    container.frame.origin.x = 0
                }
                // Verhindert das Dimmen der Karte auf der rechten Seite
                host.view.superview?.backgroundColor = .clear
            }
        }
        view.layoutIfNeeded()
    }

    // MARK: - Presentation
    private func updatePanelPresentation(animated: Bool) {
        let hasPanel = (selectedCountry != nil) || showAppearancePanel
        
        if !hasPanel {
            sheetPanelHost?.dismiss(animated: animated)
            sheetPanelHost = nil
            return
        }

        if sheetPanelHost == nil {
            let host = UIHostingController(rootView: currentPanelContentView())
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .pageSheet
            
            if let sheet = host.sheetPresentationController {
                configureSheet(sheet)
            }
            
            sheetPanelHost = host
            present(host, animated: animated)
        } else {
            sheetPanelHost?.rootView = currentPanelContentView()
            updateContentSizeAndPosition()
        }
    }

    private func configureSheet(_ sheet: UISheetPresentationController) {
        sheet.sourceView = bottomSheetAnchorView // Bindet das Sheet an unseren Anker
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true // Beachtet preferredContentSize
        sheet.prefersGrabberVisible = true
        sheet.largestUndimmedDetentIdentifier = .large // Karte bleibt interaktiv
        
        let collapsed = UISheetPresentationController.Detent.custom(identifier: .init("collapsed")) { _ in 130 }
        sheet.detents = [collapsed, .medium(), .large()]
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }

    private func currentPanelContentView() -> AnyView {
        if let country = selectedCountry {
            return AnyView(CountryQuickActionPanelView(country: country, onClose: { self.selectedCountry = nil }))
        } else if showAppearancePanel {
            let binding = Binding<MapAppearance>(get: { self.appearance }, set: { self.appearance = $0 })
            return AnyView(MapAppearancePanelView(appearance: binding, onClose: { self.showAppearancePanel = false }))
        }
        return AnyView(EmptyView())
    }
}
