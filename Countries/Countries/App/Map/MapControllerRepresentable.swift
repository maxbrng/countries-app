//
//  MapControllerRepresentable.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import SwiftData
import SwiftUI

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
