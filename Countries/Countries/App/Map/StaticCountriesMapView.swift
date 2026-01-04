//
//  StaticCountriesMapView.swift
//  Countries
//
//  Created by Max Breuning on 04.01.26.
//

import SwiftUI
import SwiftData
import CoreGraphics
import Foundation

// MARK: - View

struct StaticCountriesMapView: View {
    @Environment(\.modelContext) private var context

    /// If false: no hit testing / no selection / no overlay card.
    let selectionEnabled: Bool

    @State private var shapes: [RenderCountry] = []
    @State private var countriesByISO2: [String: Country] = [:]
    @State private var iso3ToIso2: [String: String] = [:]
    @State private var nameToIso2: [String: String] = [:]      // ✅ NEW (name→iso2 fallback)
    @State private var selectedISO2: String?

    init(selectionEnabled: Bool = true) {
        self.selectionEnabled = selectionEnabled
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard size.width > 0, size.height > 0 else { return }

                // Background (optional)
                // ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

                // Draw countries
                for c in shapes {
                    let path = scaledPath(c.path, in: size)

                    let fill = fillColor(for: c.iso2)
                    let stroke = strokeColor(for: c.iso2)
                    let lineWidth = strokeWidth(for: c.iso2)

                    ctx.fill(path, with: .color(fill), style: .init(eoFill: true))
                    ctx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
                }
            }
            .contentShape(Rectangle()) // receive taps anywhere
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard selectionEnabled else { return }
                        selectedISO2 = hitTest(point: value.location, size: geo.size)
                    }
            )
            .task {
                // Load DB countries once (needed for mapping fallbacks)
                if let all = try? context.fetch(FetchDescriptor<Country>()) {
                    countriesByISO2 = Dictionary(uniqueKeysWithValues: all.map { ($0.iso2.lowercased(), $0) })

                    iso3ToIso2 = Dictionary(uniqueKeysWithValues:
                        all.compactMap { c in
                            guard let iso3 = c.iso3?.lowercased(), !iso3.isEmpty else { return nil }
                            return (iso3, c.iso2.lowercased())
                        }
                    )

                    // Name→ISO2 fallback (lowercased name)
                    nameToIso2 = Dictionary(uniqueKeysWithValues:
                        all.map { c in
                            let key = c.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            return (key, c.iso2.lowercased())
                        }
                    )

                    // ✅ Logging: is France in DB / mappings?
                    print("DB countries:", all.count,
                          "iso3ToIso2:", iso3ToIso2.count,
                          "has fr in DB:", countriesByISO2["fr"] != nil,
                          "has fra mapping:", iso3ToIso2["fra"] ?? "nil",
                          "has france name mapping:", nameToIso2["france"] ?? "nil")
                }

                // Load shapes once (ISO2 preferred, ISO3 fallback, NAME fallback)
                do {
                    shapes = try CountriesGeoJSONStore.load(
                        resource: "countries",
                        iso3ToIso2: iso3ToIso2,
                        nameToIso2: nameToIso2,
                        debugFrance: true
                    )

                    // ✅ Logging: is France in Geo shapes?
                    print("Geo shapes:", shapes.count,
                          "has fr shape:", shapes.contains(where: { $0.iso2 == "fr" }))
                } catch {
                    print("GeoJSON load failed:", error)
                }
            }
            .overlay(alignment: .bottom) {
                if selectionEnabled,
                   let iso = selectedISO2,
                   let country = countriesByISO2[iso] {
                    Text(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
            .onChange(of: selectionEnabled) { _, enabled in
                if !enabled { selectedISO2 = nil }
            }
        }
    }

    // MARK: - Styling (Status → Color)

    private func fillColor(for iso2: String) -> Color {
        guard let country = countriesByISO2[iso2] else {
            return Color(uiColor: .systemFill).opacity(1)
        }

        switch country.status {
        case .visited:
            return Color(uiColor: .label).opacity(0.55)
        case .wishlist:
            return .orange.opacity(0.75)
        case .none:
            return Color(uiColor: .label).opacity(0.22)
        @unknown default:
            return Color(uiColor: .label).opacity(0.22)
        }
    }

    private func strokeColor(for iso2: String) -> Color {
        (selectionEnabled && selectedISO2 == iso2)
        ? Color(uiColor: .label)
        : Color(uiColor: .systemBackground).opacity(0.75)
    }

    private func strokeWidth(for iso2: String) -> Double {
        (selectionEnabled && selectedISO2 == iso2) ? 1.2 : 0.4
    }

    // MARK: - Geometry helpers

    /// Scale normalized (0..1) CGPath to view size
    private func scaledPath(_ cgPath: CGPath, in size: CGSize) -> Path {
        var t = CGAffineTransform(scaleX: size.width, y: size.height)
        let scaled = cgPath.copy(using: &t) ?? cgPath
        return Path(scaled)
    }

    /// Hit test: check from last to first so later drawn shapes win
    private func hitTest(point: CGPoint, size: CGSize) -> String? {
        for c in shapes.reversed() {
            var t = CGAffineTransform(scaleX: size.width, y: size.height)
            let scaled = c.path.copy(using: &t) ?? c.path
            if scaled.contains(point, using: .evenOdd, transform: .identity) {
                return c.iso2
            }
        }
        return nil
    }
}

// MARK: - GeoJSON Store

final class CountriesGeoJSONStore {

    static func load(
        resource: String = "countries",
        iso3ToIso2: [String: String],
        nameToIso2: [String: String],
        debugFrance: Bool = false
    ) throws -> [RenderCountry] {

        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        let fc = try JSONDecoder().decode(GeoJSON.FeatureCollection.self, from: data)

        var result: [RenderCountry] = []
        result.reserveCapacity(fc.features.count)

        let isoKeys = ["ISO_A2", "iso_a2", "ISO2", "ISO_A3", "iso_a3", "ADM0_A3"]
        let nameKeys = ["admin", "name", "ADMIN", "NAME", "name_en", "NAME_EN"]

        for f in fc.features {
            let props = f.properties ?? [:]

            let rawISO = props.firstString(for: isoKeys)?.lowercased()
            let rawName = props.firstString(for: nameKeys)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            // ✅ DEBUG: print France feature props once
            if debugFrance, let n = rawName, n == "france" {
                print("=== FRANCE FEATURE ===")
                for k in (isoKeys + nameKeys) {
                    print("  \(k):", props[k]?.stringValue ?? "nil")
                }
            }

            // Resolve ISO2
            let iso2: String?
            if let rawISO, rawISO != "-99" {
                if rawISO.count == 2 {
                    iso2 = rawISO
                } else if rawISO.count == 3 {
                    iso2 = iso3ToIso2[rawISO]
                } else {
                    iso2 = nil
                }
            } else {
                // ISO missing or -99 -> fallback by name (France case in your data)
                if let rawName {
                    iso2 = nameToIso2[rawName]
                } else {
                    iso2 = nil
                }
            }

            guard let iso2, iso2.count == 2 else { continue }

            let path = PathBuilder.makePath(from: f.geometry)
            result.append(RenderCountry(id: iso2, iso2: iso2, path: path))
        }

        return result
    }
}

// MARK: - Projection + Path Building

enum Projection {
    /// Equirectangular (Plate Carrée) projection to normalized coordinates (0..1).
    static func project(lon: Double, lat: Double) -> CGPoint {
        let x = (lon + 180.0) / 360.0
        let y = (90.0 - lat) / 180.0
        return CGPoint(x: x, y: y)
    }
}

enum PathBuilder {

    /// Build a normalized CGPath (0..1) for Polygon or MultiPolygon.
    /// Holes are supported via even-odd fill rule in Canvas.
    static func makePath(from geometry: GeoJSON.Geometry) -> CGPath {
        let path = CGMutablePath()

        func addRing(_ ring: [[Double]]) {
            guard ring.count >= 2 else { return }
            let first = ring[0]
            let p0 = Projection.project(lon: first[0], lat: first[1])
            path.move(to: p0)

            for coord in ring.dropFirst() {
                let p = Projection.project(lon: coord[0], lat: coord[1])
                path.addLine(to: p)
            }
            path.closeSubpath()
        }

        switch geometry {
        case .polygon(let rings):
            for ring in rings { addRing(ring) }

        case .multiPolygon(let polys):
            for poly in polys {
                for ring in poly { addRing(ring) }
            }
        }

        return path
    }
}

// MARK: - GeoJSON Decoding (robust mixed-type properties)

enum GeoJSON {
    struct FeatureCollection: Decodable {
        let type: String
        let features: [Feature]
    }

    struct Feature: Decodable {
        let type: String
        let properties: [String: JSONValue]?
        let geometry: Geometry
    }

    enum Geometry: Decodable {
        case polygon([[[Double]]])        // [[[lon,lat]]] rings
        case multiPolygon([[[[Double]]]]) // [[[[lon,lat]]]]

        enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)

            switch type {
            case "Polygon":
                self = .polygon(try c.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon":
                self = .multiPolygon(try c.decode([[[[Double]]]].self, forKey: .coordinates))
            default:
                self = .polygon([])
            }
        }
    }
}

/// Minimal JSON "Any" type
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { self = .null; return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let n = try? c.decode(Double.self) { self = .number(n); return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
            if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let s):
            return s
        case .number(let n):
            if n.rounded() == n { return String(Int(n)) }
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        default:
            return nil
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func firstString(for keys: [String]) -> String? {
        for k in keys {
            if let v = self[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty {
                return v
            }
        }

        // case-insensitive fallback
        let lower = Set(keys.map { $0.lowercased() })
        for (k, v) in self where lower.contains(k.lowercased()) {
            if let s = v.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }

        return nil
    }
}

// MARK: - Render Model

struct RenderCountry: Identifiable {
    let id: String      // iso2
    let iso2: String
    let path: CGPath    // normalized (0..1)
}
