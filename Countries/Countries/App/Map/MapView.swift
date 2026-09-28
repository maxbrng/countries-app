//
//  MapView.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

/// Root SwiftUI content of the map screen. Built once by ``MapViewController``
/// and driven entirely by ``MapScreenModel``.
struct MapView: View {

    /// Shared map state. Both renderers and the toolbar read and write it.
    @Bindable var model: MapScreenModel

    /// Invoked by the close button; the controller pops the navigation stack.
    let onClose: () -> Void

    /// Zoom the interactive flat map opens at. Slightly above the fit scale, so the
    /// map starts filling the screen rather than sitting inside it.
    private static let initialFlatMapZoom: CGFloat = 1.5

    var body: some View {

        ZStack {
            switch model.appearance {
            case .twoD:
                FlatMapView(detail: .interactive,
                            projectionMode: ShapeRequest.interactiveMap.projection,
                            initialStartZoom: Self.initialFlatMapZoom,
                            selectedCountry: $model.selectedCountry,
                            filter: $model.filter)
            case .threeD:
                GlobeMapView(selectedCountry: $model.selectedCountry)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "chevron.left", action: onClose)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "globe") {
                    model.showAppearancePanel = true
                }
            }
        }
    }
}
