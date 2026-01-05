//
//  GlobeMapView.swift
//  Countries
//
//  Created by Max Breuning on 05.01.26.
//

import SwiftUI
import MapKit
import SwiftData

// MARK: - Models
struct CountryShape: Identifiable {
    let id: String
    let iso2: String
    let polygons: [[CLLocationCoordinate2D]]
    let center: CLLocationCoordinate2D
    let boundingBox: MKMapRect
}

struct GlobeMapView: View {
    @Environment(\.modelContext) private var context
    
    @State private var countryShapes: [CountryShape] = []
    @State private var countriesByISO2: [String: Country] = [:]
    @State private var selectedISO2: String? = nil
    @State private var isLoading = true
    
    @Binding var selectedCountry: Country?
    
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 20, longitude: 0), distance: 25_000_000)
    )
    
    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position) {
                    if !isLoading {
                        ForEach(countryShapes) { shape in
                            let isSelected = selectedISO2 == shape.iso2
                            let statusColor = fillColor(for: shape.iso2, isSelected: isSelected)
                            
                            ForEach(0..<shape.polygons.count, id: \.self) { i in
                                MapPolygon(coordinates: shape.polygons[i])
                                    .foregroundStyle(statusColor)
                                    .stroke(isSelected ? .white : .white.opacity(0.5), lineWidth: isSelected ? 1.5 : 0.7)
                            }
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .onTapGesture { screenPoint in
                    handleTap(at: screenPoint, proxy: proxy)
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                
                if isLoading {
                    loadingOverlay
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await loadAllData() }
    }
    
    private func handleTap(at point: CGPoint, proxy: MapProxy) {
        guard let coordinate = proxy.convert(point, from: .local) else { return }
        let mapPoint = MKMapPoint(coordinate)
        
        let foundCountry = countryShapes.first { shape in
            guard shape.boundingBox.contains(mapPoint) else { return false }
            return shape.polygons.contains { ring in
                isCoordinate(coordinate, inPath: ring)
            }
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let newISO = foundCountry?.iso2 {
                if selectedISO2 == newISO {
                    selectedISO2 = nil
                    selectedCountry = nil
                } else {
                    selectedCountry = countriesByISO2[newISO]
                    selectedISO2 = newISO
                    focusCountry(iso2: newISO)
                }
            } else {
                selectedISO2 = nil
            }
        }
    }
    
    private func focusCountry(iso2: String) {
        guard let shape = countryShapes.first(where: { $0.iso2 == iso2 }) else { return }
        
        let width = shape.boundingBox.size.width
        let height = shape.boundingBox.size.height
        let diagonal = sqrt(width * width + height * height)
        
        // Logarithmische Distanz-Berechnung:
        // Verhindert zu weites Rauszoomen bei kleinen Ländern wie Spanien oder Deutschland
        let scaleLog = log10(diagonal / 100_000 + 1)
        let dynamicFactor = 1.05 + (scaleLog * 0.42)
        
        let dynamicDistance = (diagonal * dynamicFactor).clamped(2_800_000, 20_000_000)
        
        withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
            position = .camera(MapCamera(centerCoordinate: shape.center, distance: dynamicDistance))
        }
    }

    private func isCoordinate(_ probe: CLLocationCoordinate2D, inPath path: [CLLocationCoordinate2D]) -> Bool {
        var isInside = false
        var j = path.count - 1
        for i in 0..<path.count {
            if (path[i].latitude < probe.latitude && path[j].latitude >= probe.latitude ||
                path[j].latitude < probe.latitude && path[i].latitude >= probe.latitude) {
                if (path[i].longitude + (probe.latitude - path[i].latitude) / (path[j].latitude - path[i].latitude) * (path[j].longitude - path[i].longitude) < probe.longitude) {
                    isInside.toggle()
                }
            }
            j = i
        }
        return isInside
    }
    
    private func loadAllData() async {
        var iso3To2: [String: String] = [:]
        var nameTo2: [String: String] = [:]
        
        if let all = try? context.fetch(FetchDescriptor<Country>()) {
            self.countriesByISO2 = Dictionary(uniqueKeysWithValues: all.map { ($0.iso2.lowercased(), $0) })
            for c in all {
                iso3To2[c.iso3?.lowercased() ?? ""] = c.iso2.lowercased()
                nameTo2[c.nameEnglish.lowercased()] = c.iso2.lowercased()
            }
        }
        
        let shapes = await Task.detached(priority: .userInitiated) {
            return (try? await GlobeGeoJSONLoader.load(resource: "countries", iso3ToIso2: iso3To2, nameToIso2: nameTo2)) ?? []
        }.value
        
        await MainActor.run {
            withAnimation {
                self.countryShapes = shapes
                self.isLoading = false
            }
        }
    }
    
    private func fillColor(for iso2: String, isSelected: Bool) -> Color {
        if isSelected { return Color.blue.opacity(0.5) }
        if let country = countriesByISO2[iso2] {
            switch country.status {
            case .visited: return Color.blue.opacity(0.3)
            case .wishlist: return Color.orange.opacity(0.4)
            default: return Color.white.opacity(0.1)
            }
        }
        return Color.white.opacity(0.05)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 15) {
            ProgressView().tint(.white)
            Text("Weltkarte laden...").foregroundStyle(.white).font(.caption.bold())
        }
        .padding(25).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Loader
struct GlobeGeoJSONLoader {
    static func load(resource: String, iso3ToIso2: [String: String], nameToIso2: [String: String]) async throws -> [CountryShape] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson") else { return [] }
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(GeoJSONRoot.self, from: data)
        
        return root.features.compactMap { feature -> CountryShape? in
            let props = feature.properties
            var iso2: String? = nil
            
            if let a2 = props.firstString(for: ["ISO_A2", "iso_a2", "ISO2", "POSTAL"]), a2 != "-99" {
                iso2 = a2.lowercased()
            }
            if iso2 == nil, let a3 = props.firstString(for: ["ISO_A3", "iso_a3"]), let m = iso3ToIso2[a3.lowercased()] {
                iso2 = m
            }
            if iso2 == nil, let n = props.firstString(for: ["NAME", "name", "admin"]), let m = nameToIso2[n.lowercased()] {
                iso2 = m
            }
            
            guard let finalISO2 = iso2, finalISO2.count == 2 else { return nil }
            let mkCoords = feature.geometry.toMapKitCoordinates()
            guard !mkCoords.isEmpty else { return nil }
            
            var mainlandRing = mkCoords[0]
            var maxPoints = 0
            for ring in mkCoords {
                if ring.count > maxPoints {
                    maxPoints = ring.count
                    mainlandRing = ring
                }
            }
            
            let center = CLLocationCoordinate2D(
                latitude: mainlandRing.map(\.latitude).reduce(0, +) / Double(mainlandRing.count),
                longitude: mainlandRing.map(\.longitude).reduce(0, +) / Double(mainlandRing.count)
            )
            
            let allPoints = mkCoords.flatMap { $0 }.map { MKMapPoint($0) }
            let minX = allPoints.map(\.x).min() ?? 0
            let maxX = allPoints.map(\.x).max() ?? 0
            let minY = allPoints.map(\.y).min() ?? 0
            let maxY = allPoints.map(\.y).max() ?? 0
            
            return CountryShape(
                id: finalISO2, iso2: finalISO2, polygons: mkCoords,
                center: center, boundingBox: MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
    }
}

// MARK: - GeoJSON Models
struct GeoJSONRoot: Decodable { let features: [GeoJSONFeature] }
struct GeoJSONFeature: Decodable { let properties: [String: GeoJSONValue]; let geometry: GeoJSONGeometry }
enum GeoJSONValue: Decodable {
    case string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else { self = .null }
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        if case .number(let n) = self { return String(format: "%.0f", n) }
        return nil
    }
}
extension Dictionary where Key == String, Value == GeoJSONValue {
    func firstString(for keys: [String]) -> String? {
        for k in keys { if let v = self[k]?.stringValue { return v } }
        return nil
    }
}
struct GeoJSONGeometry: Decodable {
    let type: String
    let coordinates: GeoJSONCoordinates
    enum GeoJSONCoordinates: Decodable {
        case polygon([[[Double]]]), multiPolygon([[[[Double]]]])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let p = try? container.decode([[[Double]]].self) { self = .polygon(p) }
            else { self = .multiPolygon(try container.decode([[[[Double]]]].self)) }
        }
    }
    func toMapKitCoordinates() -> [[CLLocationCoordinate2D]] {
        switch coordinates {
        case .polygon(let rings): return rings.map { $0.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) } }
        case .multiPolygon(let polys): return polys.flatMap { $0.map { $0.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) } } }
        }
    }
}

extension Double {
    func clamped(_ minV: Double, _ maxV: Double) -> Double {
        return min(max(self, minV), maxV)
    }
}
