//
//  CountriesMapView.swift
//  Countries
//
//  Created by Max Breuning on 04.01.26.
//


import SwiftUI
import MapKit
import SwiftData

struct CountriesMapView: UIViewRepresentable {

    @Environment(\.modelContext) private var context
    @Binding var selectedCountry: Country?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        // Show the whole world initially
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360)
        )
        map.setRegion(worldRegion, animated: false)

        // Add tap recognizer for overlay hit-testing
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: CountriesMapView
        var countriesByISO: [String: Country] = [:]
        private var selectedOverlay: CountryOverlay?

        private var overlaysLoaded = false
        private var pendingOverlays: [CountryOverlay] = []

        init(_ parent: CountriesMapView) {
            self.parent = parent
            super.init()

            // SwiftData → Dictionary
            if let all = try? parent.context.fetch(FetchDescriptor<Country>()) {
                countriesByISO = Dictionary(uniqueKeysWithValues:
                    all.map { ($0.iso2.lowercased(), $0) }
                )
            }

            prepareOverlays()
        }

        private func prepareOverlays() {
            // Load once
            guard pendingOverlays.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let overlays = (try? GeoJSONLoader.load(from: "countries")) ?? []
                DispatchQueue.main.async { [weak self] in
                    self?.pendingOverlays = overlays
                }
            }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered, !overlaysLoaded else { return }
            // Avoid adding overlays when the drawable size is zero
            guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }

            overlaysLoaded = true
            if !pendingOverlays.isEmpty {
                mapView.addOverlays(pendingOverlays)
                // Zoom to overlays union rect
                let union = pendingOverlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
                if !union.isNull {
                    mapView.setVisibleMapRect(union, edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16), animated: false)
                }
            }
        }

        // Renderer
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? CountryOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: poly)
            let linked = countriesByISO[poly.isoCode] != nil
            let isSelected = (poly === selectedOverlay)

            if isSelected {
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.55)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 1.0
            } else {
                renderer.fillColor = linked ? UIColor.systemBlue.withAlphaComponent(0.35)
                                             : UIColor.systemGray.withAlphaComponent(0.15)
                renderer.strokeColor = UIColor.black.withAlphaComponent(0.3)
                renderer.lineWidth = 0.5
            }
            return renderer
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let tapPoint = gesture.location(in: mapView)

            // Iterate overlays top-to-bottom for proper z-order hit testing
            var newlySelected: CountryOverlay?
            for overlay in mapView.overlays.reversed() {
                guard let poly = overlay as? CountryOverlay else { continue }
                // Use existing renderer if available, otherwise create one
                let renderer = mapView.renderer(for: poly) as? MKPolygonRenderer ?? MKPolygonRenderer(polygon: poly)
                // Convert tap to renderer space and test against path
                let mapCoordinate = mapView.convert(tapPoint, toCoordinateFrom: mapView)
                let mapPoint = MKMapPoint(mapCoordinate)
                let rendererPoint = renderer.point(for: mapPoint)
                if let path = renderer.path, path.contains(rendererPoint) {
                    newlySelected = poly
                    break
                }
            }

            // Update selection and SwiftUI binding
            selectedOverlay = newlySelected
            if let iso = newlySelected?.isoCode {
                parent.selectedCountry = countriesByISO[iso]
            } else {
                parent.selectedCountry = nil
            }

            // Refresh rendering to reflect selection state
            mapView.setNeedsDisplay()
        }
    }
}
