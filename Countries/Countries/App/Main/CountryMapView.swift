//
//  CountryMapView.swift
//

import SwiftUI
import MapKit

/// A SwiftUI wrapper around MKMapView that displays country overlays with coloring based on state,
/// supports tap handling on countries, and can be configured for interactivity.
struct CountryMapView: UIViewRepresentable {
    @Binding var states: [String: CountriesViewModel.CountryState]
    var selectedCountry: String?
    var isInteractive: Bool
    var onTapCountry: ((String) -> Void)?
    var initialRegion: MKCoordinateRegion
    var resourceName: String
    var resourceExtension: String
    var resourceBundle: Bundle
    var resourceSubdirectory: String?

    init(
        states: Binding<[String: CountriesViewModel.CountryState]>,
        selectedCountry: String? = nil,
        isInteractive: Bool,
        onTapCountry: ((String) -> Void)? = nil,
        initialRegion: MKCoordinateRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)),
        resourceName: String = "countries",
        resourceExtension: String = "geojson",
        resourceBundle: Bundle = .main,
        resourceSubdirectory: String? = nil
    ) {
        self._states = states
        self.selectedCountry = selectedCountry
        self.isInteractive = isInteractive
        self.onTapCountry = onTapCountry
        self.initialRegion = initialRegion
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.resourceBundle = resourceBundle
        self.resourceSubdirectory = resourceSubdirectory
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.mapType = .mutedStandard
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isScrollEnabled = isInteractive
        mapView.isZoomEnabled = isInteractive
        mapView.isUserInteractionEnabled = isInteractive
        mapView.delegate = context.coordinator
        mapView.setRegion(initialRegion, animated: false)
        context.coordinator.mapView = mapView

        if isInteractive, onTapCountry != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            mapView.addGestureRecognizer(tap)
        }

        Task {
            do {
                let polygons = try await GeoJSONLoader.loadCountryOverlays(
                    fromResource: resourceName,
                    withExtension: resourceExtension,
                    in: resourceBundle,
                    subdirectory: resourceSubdirectory
                )
                await MainActor.run {
                    context.coordinator.polygons = polygons
                    mapView.addOverlays(polygons)
                }
            } catch {
                print("GeoJSON load error: \(error)")
            }
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.isScrollEnabled = isInteractive
        uiView.isZoomEnabled = isInteractive
        uiView.isUserInteractionEnabled = isInteractive
        context.coordinator.parent = self
        context.coordinator.refreshRendererStyles()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var polygons: [MKPolygon] = []
        var parent: CountryMapView

        init(parent: CountryMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.lineWidth = 0.5
                renderer.strokeColor = UIColor.clear
                renderer.fillColor = fillColor(for: polygon)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func refreshRendererStyles() {
            guard let mapView = mapView else { return }
            for overlay in mapView.overlays {
                guard let polygon = overlay as? MKPolygon,
                      let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer else { continue }
                renderer.fillColor = fillColor(for: polygon)
                renderer.invalidatePath()
            }
            mapView.setNeedsDisplay()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let viewPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(viewPoint, toCoordinateFrom: mapView)
            let mapPoint = MKMapPoint(coordinate)

            for polygon in polygons {
                guard let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer else { continue }
                let rendererPoint = renderer.point(for: mapPoint)
                if let path = renderer.path, path.contains(rendererPoint) {
                    if let iso = polygon.title, !iso.isEmpty {
                        parent.onTapCountry?(iso)
                    }
                    break
                }
            }
        }

        private func fillColor(for polygon: MKPolygon) -> UIColor {
            let iso = polygon.title ?? ""
            if let selected = parent.selectedCountry, selected == iso {
                return UIColor.systemBlue.withAlphaComponent(0.8)
            }
            switch parent.states[iso] {
            case .some(.visited):
                return UIColor.systemGreen.withAlphaComponent(0.8)
            case .some(.selected):
                return UIColor.systemBlue.withAlphaComponent(0.8)
            default:
                return UIColor.black.withAlphaComponent(0.8)
            }
        }
    }
}

