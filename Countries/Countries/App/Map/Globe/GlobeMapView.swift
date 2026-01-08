//
//  GlobeMapView.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import MapKit
import SwiftData

struct GlobeMapView: View {

    @Query private var countries: [Country]
    @Binding private var selectedCountry: Country?

    @State private var viewModel = GlobeMapViewModel()
    @State private var selectedISO2: String?

    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 20, longitude: 0), distance: 25_000_000)
    )

    init(selectedCountry: Binding<Country?>) {
        self._selectedCountry = selectedCountry
        _countries = Query()
    }

    var body: some View {
        
        MapReader { proxy in
            
            ZStack {
                
                Map(position: $cameraPosition) {
                    
                    if !viewModel.isLoading {
                        ForEach(viewModel.shapes) { shape in
                            
                            let isSelected = selectedISO2 == shape.iso2
                            let fillColor = fillColor(for: shape.iso2, isSelected: isSelected)

                            ForEach(shape.polygons.indices, id: \.self) { index in
                                
                                MapPolygon(coordinates: shape.polygons[index])
                                    .foregroundStyle(fillColor)
                                    .stroke(isSelected ? .white : .white.opacity(0.5), lineWidth: isSelected ? 1.5 : 0.7)
                            }
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .onTapGesture { point in
                    handleTap(at: point, mapProxy: proxy)
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                if viewModel.isLoading {
                    loadingOverlay
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await reloadData() }
        .onChange(of: countries) { _, _ in
            Task { @MainActor in await reloadData() }
        }
    }

    // MARK: - Data

    @MainActor
    private func reloadData() async {
        viewModel.updateCountryIndex(countries: countries)
        await viewModel.loadShapes()
    }

    // MARK: - Interaction

    private func handleTap(at point: CGPoint, mapProxy: MapProxy) {
        
        guard let coordinate = mapProxy.convert(point, from: .local) else { return }
        
        let mapPoint = MKMapPoint(coordinate)

        // Filtere erst alle Länder, deren Bounding Box den Punkt überhaupt enthält
        let candidateShapes = viewModel.shapes.filter { $0.boundingBox.contains(mapPoint) }

        // Nur für diese (meist nur 1-2 Länder) den teuren Polygon-Check machen
        let foundCountry = candidateShapes.first { shape in
            shape.polygons.contains {
                isCoordinate(coordinate, inside: $0)
            }
        }
            
        if let newISO2 = foundCountry?.iso2 {
            
            if selectedISO2 == newISO2 {
                selectedISO2 = nil
                selectedCountry = nil
            } else {
                selectedISO2 = newISO2
                selectedCountry = viewModel.countryIndex.countriesByISO2[newISO2]
                focusCountry(iso2: newISO2)
            }
        } else {
            selectedISO2 = nil
            selectedCountry = nil
        }
    }

    private func focusCountry(iso2: String) {
        
        guard let shape = viewModel.shapes.first(where: { $0.iso2 == iso2 }) else { return }

        let width = shape.boundingBox.size.width
        let height = shape.boundingBox.size.height
        let diagonal = sqrt(width * width + height * height)

        let scaleLog = log10(diagonal / 100_000 + 1)
        let dynamicFactor = 1.05 + (scaleLog * 0.42)
        let dynamicDistance = (diagonal * dynamicFactor).clamped(2_800_000, 20_000_000)

        withAnimation(.spring(response: 2.5, dampingFraction: 1.0)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: shape.center, distance: dynamicDistance))
        }
    }

    // MARK: - Hit test

    private func isCoordinate(_ probe: CLLocationCoordinate2D, inside polygon: [CLLocationCoordinate2D]) -> Bool {
        
        var isInside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]

            let intersectsLatitudeBand =
            (a.latitude < probe.latitude && b.latitude >= probe.latitude) ||
            (b.latitude < probe.latitude && a.latitude >= probe.latitude)

            if intersectsLatitudeBand {
                let longitudeAtProbeLatitude =
                a.longitude + (probe.latitude - a.latitude) / (b.latitude - a.latitude) * (b.longitude - a.longitude)

                if longitudeAtProbeLatitude < probe.longitude {
                    isInside.toggle()
                }
            }
            j = i
        }

        return isInside
    }

    // MARK: - Styling

    private func fillColor(for iso2: String, isSelected: Bool) -> Color {
        
        //if isSelected { return .gray.opacity(0.5) }

        if let country = viewModel.countryIndex.countriesByISO2[iso2] {
            
            switch country.status {
            case .visited:
                return .blue.opacity(0.3)
                
            case .wishlist:
                return .orange.opacity(0.4)
                
            default:
                return .white.opacity(0.1)
            }
        }
        return .white.opacity(0.05)
    }

    private var loadingOverlay: some View {
        
        VStack(spacing: 15) {
            ProgressView().tint(.white)
            Text("Loading globe...").foregroundStyle(.white).font(.caption.bold())
        }
        .padding(25)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private extension Double {
    func clamped(_ minV: Double, _ maxV: Double) -> Double {
        min(max(self, minV), maxV)
    }
}
