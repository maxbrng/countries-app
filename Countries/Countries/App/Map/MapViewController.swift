//
//  MapViewController.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import SwiftData
import SwiftUI
import UIKit

/// Hosts the SwiftUI map and adapts the UIKit lifecycle the sheet chain needs.
///
/// Two jobs, and only two. The map itself is SwiftUI, built exactly once in
/// ``setUpMapHost()``; replacing the root view on every state change is what previously left
/// the map blank and the sheet stack stuck. Everything about the stacked sheets - presenting
/// them, sizing them, rotating them, publishing what is on screen back into
/// ``MapScreenModel`` - belongs to ``MapSheetCoordinator``, which this controller forwards its
/// lifecycle callbacks to.
final class MapViewController: UIViewController {

    // MARK: - State

    /// The map's state. The SwiftUI layer writes the intent half, the coordinator the rest.
    private let model = MapScreenModel()

    /// SwiftData context forwarded into the map and into every presented sheet.
    private let modelContext: ModelContext

    /// Owner of the stacked sheet chain.
    ///
    /// - Note: `lazy` because it takes this controller as its host, which does not exist yet
    ///   while the stored properties are being initialised.
    private lazy var sheets = MapSheetCoordinator(host: self,
                                                  model: model,
                                                  modelContext: modelContext)

    /// Kept fresh by `updateUIViewController` so the close button always pops the current stack.
    var path: Binding<NavigationPath>?

    /// Hosting controller for the SwiftUI map.
    ///
    /// - Note: Implicitly unwrapped on purpose. It is assigned in `viewDidLoad()`
    ///   and is never nil afterwards for the controller's lifetime, which is the
    ///   pattern Apple prescribes for programmatically created views.
    private var mapHost: UIHostingController<MapView>!

    // MARK: - Initialization

    /// Creates the map controller.
    ///
    /// - Parameter modelContext: SwiftData context handed to the map and to every sheet.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
    }

    /// Not supported: the controller is only ever created programmatically.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpMapHost()
        sheets.attach()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sheets.hostDidAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sheets.hostWillDisappear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sheets.hostDidLayoutSubviews()
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        sheets.hostWillTransition(to: size, with: coordinator)
    }

    // MARK: - Navigation

    /// Leaves the map screen: tears the sheet stack down first, then pops the
    /// navigation path so no sheet outlives its controller.
    func closeMap() {
        guard let path, !path.wrappedValue.isEmpty else { return }
        sheets.tearDownSheets()
        path.wrappedValue.removeLast()
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
}
