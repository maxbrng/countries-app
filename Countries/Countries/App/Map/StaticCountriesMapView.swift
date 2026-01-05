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

    enum RenderMode {
        /// Old behavior (fills full view, can distort).
        case stretch
        /// Aspect-correct world rect (no distortion).
        case aspectFit
    }

    enum ProjectionMode: Equatable {
        /// Plate Carrée / Equirectangular (classic atlas look). Aspect ~ 2:1.
        case plateCarree
        /// Web Mercator (MapKit / Google-like feel). Aspect ~ 1:1 in normalized world.
        case webMercator
    }

    let selectionEnabled: Bool
    let interactiveEnabled: Bool
    let labelsEnabled: Bool
    let renderMode: RenderMode
    let projectionMode: ProjectionMode

    /// Only relevant for aspectFit: if true, initial view is zoomed so the world-rect height fills the viewport height.
    let aspectFitStartsZoomed: Bool

    // Data
    @State private var shapes: [RenderCountry] = []
    @State private var countriesByISO2: [String: Country] = [:]
    @State private var iso3ToIso2: [String: String] = [:]
    @State private var nameToIso2: [String: String] = [:]
    @State private var selectedISO2: String?

    // Interaction state (pan/zoom)
    @State private var baseScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    private let minUserScale: CGFloat = 1
    private let maxUserScale: CGFloat = 10

    init(
        selectionEnabled: Bool = true,
        interactiveEnabled: Bool = false,
        labelsEnabled: Bool = true,
        renderMode: RenderMode = .stretch,
        projectionMode: ProjectionMode = .webMercator,
        aspectFitStartsZoomed: Bool = true
    ) {
        self.selectionEnabled = selectionEnabled
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.renderMode = renderMode
        self.projectionMode = projectionMode
        self.aspectFitStartsZoomed = aspectFitStartsZoomed
    }

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size

            // Viewport is the whole view. We draw the world into "worldRect".
            let viewportRect = CGRect(origin: .zero, size: viewSize)
            let worldRect = computeWorldRect(in: viewportRect, mode: renderMode, projection: projectionMode)

            // Initial scale for aspectFit "starts zoomed" (height fills the screen).
            let initialScale = computeInitialCameraScale(viewport: viewportRect, world: worldRect)

            // Effective camera scale: initialScale * userScale
            let userScale = currentUserScale
            let cameraScale = (renderMode == .aspectFit && aspectFitStartsZoomed) ? (initialScale * userScale) : userScale

            // Pan clamp should be based on worldRect + cameraScale.
            let offset = clampedOffset(viewport: viewportRect, world: worldRect, cameraScale: cameraScale)

            Canvas { ctx, canvasSize in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }

                // 1) Draw shapes with camera transform (pan/zoom)
                var drawCtx = ctx
                if interactiveEnabled {
                    let center = CGPoint(x: worldRect.midX, y: worldRect.midY)
                    drawCtx.translateBy(x: center.x, y: center.y)
                    drawCtx.translateBy(x: offset.width, y: offset.height)
                    drawCtx.scaleBy(x: cameraScale, y: cameraScale)
                    drawCtx.translateBy(x: -center.x, y: -center.y)
                }

                for c in shapes {
                    let path = scaledPath(c.path, into: worldRect)

                    let fill = fillColor(for: c.iso2)
                    let stroke = strokeColor(for: c.iso2)

                    // Keep stroke visually stable even when zooming in
                    let lineWidth = strokeWidth(for: c.iso2) / (interactiveEnabled ? cameraScale : 1)

                    drawCtx.fill(path, with: .color(fill), style: .init(eoFill: true))
                    drawCtx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
                }

                // 2) Labels
                // Rule: only when interactive + selection + enabled
                if shouldDrawLabels {
                    for c in shapes {
                        guard let country = countriesByISO2[c.iso2] else { continue }
                        let name = country.displayName(preferredLanguageCodes: Locale.preferredLanguages)
                        if name.isEmpty { continue }

                        // Base anchor (normalized → worldRect)
                        let basePoint = CGPoint(
                            x: worldRect.minX + c.labelAnchor.x * worldRect.width,
                            y: worldRect.minY + c.labelAnchor.y * worldRect.height
                        )

                        // Convert anchor to screen point (apply camera transform to the POINT only)
                        let screenPoint = interactiveEnabled
                            ? transform(point: basePoint, around: worldRect, scale: cameraScale, offset: offset)
                            : basePoint

                        // Compute bbox size in screen space (so fit checks work with zoom)
                        let bbox = scaledPath(c.path, into: worldRect).boundingRect
                        let bboxW = bbox.width * (interactiveEnabled ? cameraScale : 1)
                        let bboxH = bbox.height * (interactiveEnabled ? cameraScale : 1)

                        // Font scaling rule:
                        // - zooming IN: do NOT make font bigger
                        // - zooming OUT: make font bigger
                        let baseFont: CGFloat = 10
                        let fontScale = min(1.0, 1.0 / max(cameraScale, 0.0001)) // >1 only when zoomed out
                        let fontSize = (baseFont * fontScale).clamped(8, 14)

                        let text = Text(name)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label).opacity(0.70))

                        let resolved = ctx.resolve(text)
                        let textSize = resolved.measure(in: CGSize(
                            width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude
                        ))

                        let pad: CGFloat = 10
                        guard bboxW >= textSize.width + pad, bboxH >= textSize.height + pad else { continue }

                        ctx.draw(resolved, at: screenPoint, anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())

            // Tap selection (convert point back into world-space)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard selectionEnabled else { return }

                        let p = interactiveEnabled
                            ? untransform(point: value.location, around: worldRect, scale: cameraScale, offset: offset)
                            : value.location

                        selectedISO2 = hitTest(point: p, in: worldRect)
                    }
            )

            // Pan
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { v in
                        guard interactiveEnabled else { return }
                        gestureOffset = CGSize(width: v.translation.width, height: v.translation.height)
                    }
                    .onEnded { _ in
                        guard interactiveEnabled else { return }
                        baseOffset = CGSize(
                            width: baseOffset.width + gestureOffset.width,
                            height: baseOffset.height + gestureOffset.height
                        )
                        gestureOffset = .zero

                        // clamp
                        baseOffset = clampedOffset(viewport: viewportRect, world: worldRect, cameraScale: cameraScale)
                    }
            )

            // Zoom (user zoom factor only; cameraScale = initialScale * userScale)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in
                        guard interactiveEnabled else { return }
                        gestureScale = v
                    }
                    .onEnded { _ in
                        guard interactiveEnabled else { return }
                        baseScale = (baseScale * gestureScale).clamped(minUserScale, maxUserScale)
                        gestureScale = 1
                        baseOffset = clampedOffset(viewport: viewportRect, world: worldRect, cameraScale: cameraScale)
                    }
            )
            .task(id: projectionMode) {
                // Reload shapes if projection changes
                // Load DB countries
                if let all = try? context.fetch(FetchDescriptor<Country>()) {
                    countriesByISO2 = Dictionary(uniqueKeysWithValues: all.map { ($0.iso2.lowercased(), $0) })

                    iso3ToIso2 = Dictionary(uniqueKeysWithValues:
                        all.compactMap { c in
                            guard let iso3 = c.iso3?.lowercased(), !iso3.isEmpty else { return nil }
                            return (iso3, c.iso2.lowercased())
                        }
                    )

                    nameToIso2 = Dictionary(uniqueKeysWithValues:
                        all.map { c in
                            let key = c.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            return (key, c.iso2.lowercased())
                        }
                    )
                }

                // Load shapes with selected projection
                do {
                    shapes = try CountriesGeoJSONStore.load(
                        resource: "countries",
                        iso3ToIso2: iso3ToIso2,
                        nameToIso2: nameToIso2,
                        projectionMode: projectionMode,
                        debugFrance: false
                    )
                } catch {
                    print("GeoJSON load failed:", error)
                }

                // Reset interaction when switching projection
                baseOffset = .zero
                gestureOffset = .zero
                baseScale = 1
                gestureScale = 1
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
            .onChange(of: interactiveEnabled) { _, enabled in
                if !enabled {
                    baseScale = 1
                    gestureScale = 1
                    baseOffset = .zero
                    gestureOffset = .zero
                }
            }
        }
    }

    // Labels only when interactive + selection + enabled
    private var shouldDrawLabels: Bool {
        labelsEnabled && interactiveEnabled && selectionEnabled
    }

    // MARK: - World Rect

    private func computeWorldRect(in viewport: CGRect, mode: RenderMode, projection: ProjectionMode) -> CGRect {
        switch mode {
        case .stretch:
            return viewport
        case .aspectFit:
            let aspect = projection.worldAspect
            return aspectFitRect(in: viewport, aspect: aspect)
        }
    }

    private func aspectFitRect(in viewport: CGRect, aspect: CGFloat) -> CGRect {
        let size = viewport.size
        guard size.width > 0, size.height > 0 else { return .zero }

        let viewAspect = size.width / size.height

        if viewAspect > aspect {
            // wider: fit height
            let h = size.height
            let w = h * aspect
            let x = (size.width - w) / 2
            return CGRect(x: viewport.minX + x, y: viewport.minY, width: w, height: h)
        } else {
            // taller: fit width
            let w = size.width
            let h = w / aspect
            let y = (size.height - h) / 2
            return CGRect(x: viewport.minX, y: viewport.minY + y, width: w, height: h)
        }
    }

    private func computeInitialCameraScale(viewport: CGRect, world: CGRect) -> CGFloat {
        guard renderMode == .aspectFit, aspectFitStartsZoomed else { return 1 }
        guard world.height > 0 else { return 1 }
        return viewport.height / world.height
    }

    // MARK: - Interaction math

    private var currentUserScale: CGFloat {
        interactiveEnabled ? (baseScale * gestureScale).clamped(minUserScale, maxUserScale) : 1
    }

    private var currentOffset: CGSize {
        interactiveEnabled
            ? CGSize(width: baseOffset.width + gestureOffset.width,
                     height: baseOffset.height + gestureOffset.height)
            : .zero
    }

    private func clampedOffset(viewport: CGRect, world: CGRect, cameraScale: CGFloat) -> CGSize {
        guard interactiveEnabled else { return .zero }
        let off = currentOffset

        let contentW = world.width * cameraScale
        let contentH = world.height * cameraScale

        let maxX = max(0, (contentW - viewport.width) / 2)
        let maxY = max(0, (contentH - viewport.height) / 2)

        return CGSize(
            width: off.width.clamped(-maxX, maxX),
            height: off.height.clamped(-maxY, maxY)
        )
    }

    private func transform(point: CGPoint, around worldRect: CGRect, scale: CGFloat, offset: CGSize) -> CGPoint {
        let cx = worldRect.midX
        let cy = worldRect.midY

        var x = point.x - cx
        var y = point.y - cy

        x *= scale
        y *= scale

        x += offset.width
        y += offset.height

        x += cx
        y += cy

        return CGPoint(x: x, y: y)
    }

    private func untransform(point: CGPoint, around worldRect: CGRect, scale: CGFloat, offset: CGSize) -> CGPoint {
        let cx = worldRect.midX
        let cy = worldRect.midY

        var x = point.x - cx
        var y = point.y - cy

        x -= offset.width
        y -= offset.height

        x /= scale
        y /= scale

        x += cx
        y += cy

        return CGPoint(x: x, y: y)
    }

    // MARK: - Styling

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

    private func scaledPath(_ cgPath: CGPath, into rect: CGRect) -> Path {
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: rect.minX, y: rect.minY)
        t = t.scaledBy(x: rect.width, y: rect.height)
        let scaled = cgPath.copy(using: &t) ?? cgPath
        return Path(scaled)
    }

    private func hitTest(point: CGPoint, in worldRect: CGRect) -> String? {
        for c in shapes.reversed() {
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: worldRect.minX, y: worldRect.minY)
            t = t.scaledBy(x: worldRect.width, y: worldRect.height)
            let scaled = c.path.copy(using: &t) ?? c.path

            if scaled.contains(point, using: .evenOdd, transform: .identity) {
                return c.iso2
            }
        }
        return nil
    }
}

// MARK: - Projection mode helpers

private extension StaticCountriesMapView.ProjectionMode {
    var worldAspect: CGFloat {
        switch self {
        case .plateCarree: return 2.0
        case .webMercator: return 1.0
        }
    }
}

// MARK: - GeoJSON Store

final class CountriesGeoJSONStore {
    static func load(
        resource: String = "countries",
        iso3ToIso2: [String: String],
        nameToIso2: [String: String],
        projectionMode: StaticCountriesMapView.ProjectionMode,
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

            if debugFrance, rawName == "france" {
                print("=== FRANCE FEATURE ===")
                for k in (isoKeys + nameKeys) {
                    print("  \(k):", props[k]?.stringValue ?? "nil")
                }
            }

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
                if let rawName {
                    iso2 = nameToIso2[rawName]
                } else {
                    iso2 = nil
                }
            }

            guard let iso2, iso2.count == 2 else { continue }

            let built = PathBuilder.makePathAndLabelAnchor(from: f.geometry, projectionMode: projectionMode)
            result.append(RenderCountry(id: iso2, iso2: iso2, path: built.path, labelAnchor: built.labelAnchor))
        }

        return result
    }
}

// MARK: - Projection + Path Building

enum Projection {
    static func project(lon: Double, lat: Double, mode: StaticCountriesMapView.ProjectionMode) -> CGPoint {
        switch mode {
        case .plateCarree:
            // Plate Carrée (0..1)
            let x = (lon + 180.0) / 360.0
            let y = (90.0 - lat) / 180.0
            return CGPoint(x: x, y: y)

        case .webMercator:
            // Web Mercator normalized to 0..1
            let maxLat = 85.05112878
            let clampedLat = min(max(lat, -maxLat), maxLat)

            let x = (lon + 180.0) / 360.0

            let latRad = clampedLat * .pi / 180.0
            let merc = log(tan(.pi / 4.0 + latRad / 2.0))
            let y = (1.0 - (merc / .pi)) / 2.0

            return CGPoint(x: x, y: y)
        }
    }
}

enum PathBuilder {
    struct Built {
        let path: CGPath
        let labelAnchor: CGPoint // normalized
    }

    static func makePathAndLabelAnchor(from geometry: GeoJSON.Geometry, projectionMode: StaticCountriesMapView.ProjectionMode) -> Built {
        let path = CGMutablePath()

        var bestArea: Double = 0
        var bestCentroid: CGPoint = CGPoint(x: 0.5, y: 0.5)
        var bestBBox: CGRect = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)

        func addRing(_ ring: [[Double]]) {
            guard ring.count >= 2 else { return }
            let first = ring[0]
            let p0 = Projection.project(lon: first[0], lat: first[1], mode: projectionMode)
            path.move(to: p0)
            for coord in ring.dropFirst() {
                let p = Projection.project(lon: coord[0], lat: coord[1], mode: projectionMode)
                path.addLine(to: p)
            }
            path.closeSubpath()
        }

        func considerOuterRing(_ ring: [[Double]]) {
            let pts = ring.map { Projection.project(lon: $0[0], lat: $0[1], mode: projectionMode) }
            let (area, centroid) = polygonAreaAndCentroid(pts)
            let absArea = abs(area)
            if absArea > bestArea, centroid.x.isFinite, centroid.y.isFinite {
                bestArea = absArea
                bestCentroid = centroid
                bestBBox = bbox(of: pts)
            }
        }

        switch geometry {
        case .polygon(let rings):
            for (i, ring) in rings.enumerated() {
                addRing(ring)
                if i == 0 { considerOuterRing(ring) }
            }
        case .multiPolygon(let polys):
            for poly in polys {
                for (i, ring) in poly.enumerated() {
                    addRing(ring)
                    if i == 0 { considerOuterRing(ring) }
                }
            }
        }

        // Better-than-centroid fallback: bbox center
        let bboxCenter = CGPoint(x: bestBBox.midX, y: bestBBox.midY)
        let anchor = bestBBox.contains(bestCentroid) ? bestCentroid : bboxCenter

        return Built(path: path, labelAnchor: anchor)
    }

    private static func bbox(of pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for p in pts {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        if minX == CGFloat.greatestFiniteMagnitude { return .zero }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func polygonAreaAndCentroid(_ pts: [CGPoint]) -> (Double, CGPoint) {
        guard pts.count >= 3 else { return (0, CGPoint(x: 0.5, y: 0.5)) }

        var a: Double = 0
        var cx: Double = 0
        var cy: Double = 0

        for i in 0..<pts.count {
            let p = pts[i]
            let q = pts[(i + 1) % pts.count]
            let cross = Double(p.x * q.y - q.x * p.y)
            a += cross
            cx += (Double(p.x) + Double(q.x)) * cross
            cy += (Double(p.y) + Double(q.y)) * cross
        }

        a *= 0.5
        let denom = 6.0 * a
        if denom == 0 { return (0, CGPoint(x: 0.5, y: 0.5)) }

        return (a, CGPoint(x: cx / denom, y: cy / denom))
    }
}

// MARK: - GeoJSON Decoding

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
        case polygon([[[Double]]])
        case multiPolygon([[[[Double]]]])

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
        case .string(let s): return s
        case .number(let n):
            if n.rounded() == n { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func firstString(for keys: [String]) -> String? {
        for k in keys {
            if let v = self[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty { return v }
        }
        let lower = Set(keys.map { $0.lowercased() })
        for (k, v) in self where lower.contains(k.lowercased()) {
            if let s = v.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty { return s }
        }
        return nil
    }
}

// MARK: - Render Model

struct RenderCountry: Identifiable {
    let id: String
    let iso2: String
    let path: CGPath
    let labelAnchor: CGPoint // normalized (0..1)
}

// MARK: - Helpers

private extension Comparable {
    func clamped(_ minValue: Self, _ maxValue: Self) -> Self {
        min(max(self, minValue), maxValue)
    }
}
