//
//  MapAppearancePanelView.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//

import SwiftUI

/// Content of the appearance sheet on the map: switches the renderer between the flat
/// 2D map and the 3D globe.
///
/// - Note: The selection is written straight into the ``MapScreenModel``, which rebuilds
///   the map root for the picked ``MapAppearance``.
struct MapAppearancePanelView: View {

    // MARK: - Constants

    /// Padding of the picker.
    private enum Layout {

        /// Extra horizontal padding, so the segmented control clears the sheet edges.
        static let pickerHorizontalPadding: CGFloat = 4
    }

    // MARK: - State

    /// The map state this panel writes the appearance into.
    @Bindable var model: MapScreenModel

    // MARK: - Body

    var body: some View {
        VStack {
            Picker("Appearance", selection: $model.appearance) {
                Text(verbatim: "2D").tag(MapAppearance.twoD)
                Text(verbatim: "3D").tag(MapAppearance.threeD)
            }
            .pickerStyle(.segmented)
            .padding()
            .padding(.horizontal, Layout.pickerHorizontalPadding)
        }
    }
}
