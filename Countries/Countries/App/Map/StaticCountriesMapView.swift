//
//  StaticCountriesMapView.swift
//  Countries
//
//  Created by Max Breuning on 05.01.26.
//

import SwiftUI
import SwiftData
import CoreGraphics
import Foundation

// MARK: - View

struct StaticCountriesMapView: View {
    @Environment(\.modelContext) private var context

    enum RenderMode { case stretch, aspectFit }
    enum ProjectionMode: Equatable { case plateCarree, webMercator }

    // MARK: Config
    let selectionEnabled: Bool
    let interactiveEnabled: Bool
    let labelsEnabled: Bool
    let renderMode: RenderMode
    let projectionMode: ProjectionMode
    let aspectFitStartsZoomed: Bool

    let wrapHorizontally: Bool
    let doubleTapZoomFactor: CGFloat
    let focusOnTap: Bool
    let focusPadding: CGFloat

    let hardReloadOnRotation: Bool

    // MARK: Data
    @State private var shapes: [RenderCountry] = []
    @State private var countriesByISO2: [String: Country] = [:]
    @State private var iso3ToIso2: [String: String] = [:]
    @State private var nameToIso2: [String: String] = [:]
    @State private var selectedISO2: String?

    // MARK: Camera
    @State private var mapCenter = CGPoint(x: 0.5, y: 0.5) // normalized (0..1)
    @State private var userZoom: CGFloat = 1               // user zoom (relative to fitScale)

    private let maxUserScale: CGFloat = 40

    // Deceleration
    @State private var decelTask: Task<Void, Never>?

    // Hard reload token (only render subtree)
    @State private var reloadToken: Int = 0
    @State private var lastSize: CGSize = .zero
    @State private var didInitCameraForProjection: Bool = false

    init(
        selectionEnabled: Bool = true,
        interactiveEnabled: Bool = false,
        labelsEnabled: Bool = true,
        renderMode: RenderMode = .aspectFit,
        projectionMode: ProjectionMode = .webMercator,
        aspectFitStartsZoomed: Bool = true,
        wrapHorizontally: Bool = false,
        rubberBanding: Bool = false,
        doubleTapZoomFactor: CGFloat = 2.0,
        focusOnTap: Bool = true,
        focusPadding: CGFloat = 24,
        hardReloadOnRotation: Bool = true
    ) {
        self.selectionEnabled = selectionEnabled
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.renderMode = renderMode
        self.projectionMode = projectionMode
        self.aspectFitStartsZoomed = aspectFitStartsZoomed
        self.wrapHorizontally = wrapHorizontally
        self.doubleTapZoomFactor = doubleTapZoomFactor
        self.focusOnTap = focusOnTap
        self.focusPadding = focusPadding
        self.hardReloadOnRotation = hardReloadOnRotation
    }

    var body: some View {
        GeometryReader { geo in
            let viewport = CGRect(origin: .zero, size: geo.size)
            let worldRect = computeWorldRect(in: viewport, mode: renderMode, projection: projectionMode)

            let fitScale: CGFloat =
                (renderMode == .aspectFit && aspectFitStartsZoomed && worldRect.height > 0)
                ? (viewport.height / worldRect.height)
                : 1

            // ✅ dynamic min zoom so world always covers viewport (no empty rim -> no freeze)
            let minUserZoom = dynamicMinUserZoom(viewport: viewport, world: worldRect, fitScale: fitScale)

            ZStack {
                renderAndGestures(
                    viewport: viewport,
                    worldRect: worldRect,
                    fitScale: fitScale,
                    minUserZoom: minUserZoom
                )
                .id(reloadToken)

                if selectionEnabled,
                   let iso = selectedISO2,
                   let country = countriesByISO2[iso] {
                    VStack {
                        Spacer()
                        Text(country.displayName(preferredLanguageCodes: Locale.preferredLanguages))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding()
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .onAppear {
                if lastSize == .zero { lastSize = geo.size }
                // clamp once on appear
                clampCamera(viewport: viewport, world: worldRect, fitScale: fitScale)
            }
            .onChange(of: geo.size) { _, newSize in
                guard newSize != .zero else { return }
                let old = lastSize
                lastSize = newSize

                // re-clamp on size change (important for rotation)
                clampCamera(viewport: viewport, world: worldRect, fitScale: fitScale)

                guard hardReloadOnRotation else { return }
                guard old != .zero, old != newSize else { return }
                stopDeceleration()
                reloadToken &+= 1
            }
            .task(id: projectionMode) {
                didInitCameraForProjection = false
                await loadInitialData()
            }
            .onChange(of: selectionEnabled) { _, enabled in
                if !enabled { selectedISO2 = nil }
            }
            .onChange(of: interactiveEnabled) { _, enabled in
                if !enabled {
                    stopDeceleration()
                    withAnimation(.easeInOut) {
                        userZoom = 1
                        mapCenter = CGPoint(x: 0.5, y: 0.5)
                    }
                } else {
                    if hardReloadOnRotation { reloadToken &+= 1 }
                }
            }
        }
    }

    // MARK: - Subtree (Render + Gestures)

    @ViewBuilder
    private func renderAndGestures(viewport: CGRect, worldRect: CGRect, fitScale: CGFloat, minUserZoom: CGFloat) -> some View {

        let clampedZoom = userZoom.clamped(minUserZoom, maxUserScale)
        let totalScale = fitScale * clampedZoom
        let clampedCenter = clampCenter(mapCenter, viewport: viewport, world: worldRect, totalScale: totalScale)

        WorldMapRenderView(
            shapes: shapes,
            countriesByISO2: countriesByISO2,
            selectedISO2: selectedISO2,
            viewport: viewport,
            worldRect: worldRect,
            fitScale: fitScale,
            userZoom: clampedZoom,          // animatable
            userCenter: clampedCenter,      // animatable
            interactiveEnabled: interactiveEnabled,
            labelsEnabled: labelsEnabled && interactiveEnabled && selectionEnabled,
            selectionEnabled: selectionEnabled
        )
        .contentShape(Rectangle())
        .overlay {
            if interactiveEnabled {
                MapLikeGestureView(
                    onPanBegan: { stopDeceleration() },
                    onPanChanged: { delta in
                        applyPan(delta: delta, viewport: viewport, world: worldRect, fitScale: fitScale)
                    },
                    onPanEnded: { velocity in
                        startDeceleration(velocity: velocity, viewport: viewport, world: worldRect, fitScale: fitScale)
                        // snap hard at end
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                            clampCamera(viewport: viewport, world: worldRect, fitScale: fitScale)
                        }
                    },
                    onPinchBegan: { stopDeceleration() },
                    onPinchChanged: { scaleDelta, center in
                        applyPinch(scaleDelta: scaleDelta, center: center, viewport: viewport, world: worldRect, fitScale: fitScale)
                    },
                    onPinchEnded: {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                            clampCamera(viewport: viewport, world: worldRect, fitScale: fitScale)
                        }
                    },
                    onDoubleTap: { point in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            applyDoubleTap(at: point, viewport: viewport, world: worldRect, fitScale: fitScale)
                            clampCamera(viewport: viewport, world: worldRect, fitScale: fitScale)
                        }
                    },
                    onTap: { point in
                        handleTap(at: point, viewport: viewport, world: worldRect, fitScale: fitScale)
                    }
                )
            }
        }
    }

    // MARK: - ✅ Hard bounds without freeze

    /// Minimum zoom so the world *covers* the viewport (no empty rim possible).
    /// This prevents the “visible >= 1 => center range collapses => freeze” case entirely.
    private func dynamicMinUserZoom(viewport: CGRect, world: CGRect, fitScale: CGFloat) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0, world.width > 0, world.height > 0, fitScale > 0 else {
            return 1
        }
        // totalScale must be >= max(viewport/world) to cover in both axes
        let minTotalScale = max(viewport.width / world.width, viewport.height / world.height)
        let minUser = minTotalScale / fitScale
        return max(0.0001, minUser)
    }

    private func clampCamera(viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        let minUser = dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale)
        userZoom = userZoom.clamped(minUser, maxUserScale)

        let totalScale = fitScale * userZoom
        mapCenter = clampCenter(mapCenter, viewport: viewport, world: world, totalScale: totalScale)
    }

    /// Clamp center so viewport never looks beyond world edges.
    private func clampCenter(_ center: CGPoint, viewport: CGRect, world: CGRect, totalScale: CGFloat) -> CGPoint {
        guard viewport.width > 0, viewport.height > 0, world.width > 0, world.height > 0, totalScale > 0 else {
            return center
        }

        let visibleW = (viewport.width / totalScale) / world.width
        let visibleH = (viewport.height / totalScale) / world.height

        // because we prevent visible >= 1 with min zoom, these won't collapse anymore
        let minX = visibleW * 0.5
        let maxX = 1 - visibleW * 0.5
        let minY = visibleH * 0.5
        let maxY = 1 - visibleH * 0.5

        var x = center.x
        var y = center.y

        if wrapHorizontally {
            x = x.truncatingRemainder(dividingBy: 1)
            if x < 0 { x += 1 }
        } else {
            x = x.clamped(minX, maxX)
        }

        y = y.clamped(minY, maxY)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Tap / Focus

    private func handleTap(at point: CGPoint, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        guard selectionEnabled else { return }

        let minUser = dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale)
        let z = userZoom.clamped(minUser, maxUserScale)
        let totalScale = fitScale * z
        let c = clampCenter(mapCenter, viewport: viewport, world: world, totalScale: totalScale)

        let offset = offsetFromCenter(c, viewport: viewport, world: world, totalScale: totalScale)
        let worldPoint = untransform(point: point, viewport: viewport, totalScale: totalScale, offset: offset)

        guard let iso2 = hitTest(point: worldPoint, in: world) else {
            withAnimation(.easeInOut(duration: 0.2)) { selectedISO2 = nil }
            return
        }

        selectedISO2 = iso2

        if focusOnTap {
            stopDeceleration()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                focusCountry(iso2: iso2, viewport: viewport, world: world, fitScale: fitScale)
            }
        }
    }

    private func focusCountry(iso2: String, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        guard let shape = shapes.first(where: { $0.iso2 == iso2 }) else { return }
        let f = shape.focusBBoxNormalized
        guard f.width > 0, f.height > 0 else { return }

        let padded = viewport.insetBy(dx: focusPadding, dy: focusPadding)
        guard padded.width > 0, padded.height > 0 else { return }

        let wScale = padded.width / (f.width * world.width)
        let hScale = padded.height / (f.height * world.height)
        let targetCamScale = min(wScale, hScale)
        let targetUser = targetCamScale / max(fitScale, 0.0001)

        userZoom = targetUser.clamped(dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale), maxUserScale)

        let totalScale = fitScale * userZoom
        mapCenter = clampCenter(CGPoint(x: f.midX, y: f.midY), viewport: viewport, world: world, totalScale: totalScale)
    }

    // MARK: - Gestures

    private func applyPan(delta: CGSize, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        let minUser = dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale)
        userZoom = userZoom.clamped(minUser, maxUserScale)

        let totalScale = fitScale * userZoom
        let c = clampCenter(mapCenter, viewport: viewport, world: world, totalScale: totalScale)

        let currentOff = offsetFromCenter(c, viewport: viewport, world: world, totalScale: totalScale)
        let nextOff = CGSize(width: currentOff.width + delta.width, height: currentOff.height + delta.height)

        // compute new center from offset then clamp hard
        let raw = centerFromOffset(nextOff, viewport: viewport, world: world, totalScale: totalScale)
        mapCenter = clampCenter(raw, viewport: viewport, world: world, totalScale: totalScale)
    }

    private func applyPinch(scaleDelta: CGFloat, center: CGPoint, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        let minUser = dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale)

        let oldTotalScale = fitScale * userZoom
        let smoothDelta = pow(scaleDelta, 0.85)

        // zoom (hard clamp with dynamic min)
        let newUser = (userZoom * smoothDelta).clamped(minUser, maxUserScale)
        let newTotalScale = fitScale * newUser

        // stabilize around pinch center
        let c = clampCenter(mapCenter, viewport: viewport, world: world, totalScale: oldTotalScale)
        let currentOff = offsetFromCenter(c, viewport: viewport, world: world, totalScale: oldTotalScale)
        let newOff = zoomOffsetAroundPoint(offset: currentOff, oldScale: oldTotalScale, newScale: newTotalScale, viewport: viewport, pinchCenter: center)

        userZoom = newUser

        let raw = centerFromOffset(newOff, viewport: viewport, world: world, totalScale: newTotalScale)
        mapCenter = clampCenter(raw, viewport: viewport, world: world, totalScale: newTotalScale)
    }

    private func applyDoubleTap(at point: CGPoint, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        let minUser = dynamicMinUserZoom(viewport: viewport, world: world, fitScale: fitScale)

        let oldTotalScale = fitScale * userZoom
        let targetUser = (userZoom * doubleTapZoomFactor).clamped(minUser, maxUserScale)
        let newTotalScale = fitScale * targetUser

        let c = clampCenter(mapCenter, viewport: viewport, world: world, totalScale: oldTotalScale)
        let currentOff = offsetFromCenter(c, viewport: viewport, world: world, totalScale: oldTotalScale)
        let newOff = zoomOffsetAroundPoint(offset: currentOff, oldScale: oldTotalScale, newScale: newTotalScale, viewport: viewport, pinchCenter: point)

        userZoom = targetUser

        let raw = centerFromOffset(newOff, viewport: viewport, world: world, totalScale: newTotalScale)
        mapCenter = clampCenter(raw, viewport: viewport, world: world, totalScale: newTotalScale)
    }

    // MARK: - Math helpers

    private func offsetFromCenter(_ center: CGPoint, viewport: CGRect, world: CGRect, totalScale: CGFloat) -> CGSize {
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let worldPointX = world.minX + center.x * world.width
        let worldPointY = world.minY + center.y * world.height
        return CGSize(
            width: (camCenter.x - worldPointX) * totalScale,
            height: (camCenter.y - worldPointY) * totalScale
        )
    }

    private func centerFromOffset(_ offset: CGSize, viewport: CGRect, world: CGRect, totalScale: CGFloat) -> CGPoint {
        guard world.width > 0, world.height > 0, totalScale > 0 else { return mapCenter }
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let worldPointX = camCenter.x - (offset.width / totalScale)
        let worldPointY = camCenter.y - (offset.height / totalScale)
        let cx = (worldPointX - world.minX) / world.width
        let cy = (worldPointY - world.minY) / world.height
        return CGPoint(x: cx, y: cy)
    }

    private func zoomOffsetAroundPoint(offset: CGSize, oldScale: CGFloat, newScale: CGFloat, viewport: CGRect, pinchCenter: CGPoint) -> CGSize {
        guard oldScale > 0 else { return offset }
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let px = pinchCenter.x - camCenter.x
        let py = pinchCenter.y - camCenter.y
        let k = 1 - (newScale / oldScale)
        return CGSize(
            width: offset.width + (px - offset.width) * k,
            height: offset.height + (py - offset.height) * k
        )
    }

    private func untransform(point: CGPoint, viewport: CGRect, totalScale: CGFloat, offset: CGSize) -> CGPoint {
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        var x = point.x - camCenter.x - offset.width
        var y = point.y - camCenter.y - offset.height
        x /= totalScale
        y /= totalScale
        x += camCenter.x
        y += camCenter.y
        return CGPoint(x: x, y: y)
    }

    private func hitTest(point: CGPoint, in worldRect: CGRect) -> String? {
        for c in shapes.reversed() {
            var t = CGAffineTransform(translationX: worldRect.minX, y: worldRect.minY)
                .scaledBy(x: worldRect.width, y: worldRect.height)
            if c.path.copy(using: &t)?.contains(point, using: .evenOdd) == true { return c.iso2 }
        }
        return nil
    }

    // MARK: - Deceleration

    private func stopDeceleration() {
        decelTask?.cancel()
        decelTask = nil
    }

    private func startDeceleration(velocity: CGPoint, viewport: CGRect, world: CGRect, fitScale: CGFloat) {
        stopDeceleration()
        decelTask = Task { @MainActor in
            var v = velocity
            while !Task.isCancelled {
                let dt: CGFloat = 1.0 / 60.0
                let delta = CGSize(width: v.x * dt, height: v.y * dt)
                applyPan(delta: delta, viewport: viewport, world: world, fitScale: fitScale)

                v = CGPoint(x: v.x * 0.92, y: v.y * 0.92)
                if abs(v.x) < 5 && abs(v.y) < 5 { break }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                clampCamera(viewport: viewport, world: world, fitScale: fitScale)
            }
        }
    }

    // MARK: - World rect

    private func computeWorldRect(in viewport: CGRect, mode: RenderMode, projection: ProjectionMode) -> CGRect {
        if mode == .stretch { return viewport }
        let aspect = projection.worldAspect
        let size = viewport.size
        let viewAspect = size.width / size.height
        if viewAspect > aspect {
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
    }

    // MARK: - Loading

    private func loadInitialData() async {
        if let all = try? context.fetch(FetchDescriptor<Country>()) {
            countriesByISO2 = Dictionary(uniqueKeysWithValues: all.map { ($0.iso2.lowercased(), $0) })
            iso3ToIso2 = Dictionary(uniqueKeysWithValues: all.compactMap { c in
                guard let iso3 = c.iso3?.lowercased(), !iso3.isEmpty else { return nil }
                return (iso3, c.iso2.lowercased())
            })
            nameToIso2 = Dictionary(uniqueKeysWithValues: all.map { c in
                (c.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), c.iso2.lowercased())
            })
        }

        do {
            shapes = try CountriesGeoJSONStore.load(
                resource: "countries",
                iso3ToIso2: iso3ToIso2,
                nameToIso2: nameToIso2,
                projectionMode: projectionMode
            )
        } catch {
            print("Err:", error)
            shapes = []
        }

        stopDeceleration()

        if !didInitCameraForProjection {
            didInitCameraForProjection = true
            userZoom = 1
            mapCenter = CGPoint(x: 0.5, y: 0.5)
        }

        if hardReloadOnRotation { reloadToken &+= 1 }
    }
}

// MARK: - THE MAGIC FIX: Animatable Render View

struct WorldMapRenderView: View, Animatable {
    let shapes: [RenderCountry]
    let countriesByISO2: [String: Country]
    let selectedISO2: String?

    let viewport: CGRect
    let worldRect: CGRect
    let fitScale: CGFloat

    var userZoom: CGFloat
    var userCenter: CGPoint

    let interactiveEnabled: Bool
    let labelsEnabled: Bool
    let selectionEnabled: Bool

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(userZoom, AnimatablePair(userCenter.x, userCenter.y)) }
        set {
            userZoom = newValue.first
            userCenter = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    var body: some View {
        Canvas { ctx, _ in
            guard viewport.width > 0, viewport.height > 0 else { return }

            let currentScale = fitScale * userZoom

            let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
            let worldPointX = worldRect.minX + userCenter.x * worldRect.width
            let worldPointY = worldRect.minY + userCenter.y * worldRect.height
            let offsetX = (camCenter.x - worldPointX) * currentScale
            let offsetY = (camCenter.y - worldPointY) * currentScale

            var drawCtx = ctx

            if interactiveEnabled {
                drawCtx.translateBy(x: camCenter.x + offsetX, y: camCenter.y + offsetY)
                drawCtx.scaleBy(x: currentScale, y: currentScale)
                drawCtx.translateBy(x: -camCenter.x, y: -camCenter.y)
            }

            for c in shapes {
                let path = scaledPath(c.path, into: worldRect)
                let isSel = (selectionEnabled && selectedISO2 == c.iso2)

                let fill: Color
                if let country = countriesByISO2[c.iso2] {
                    switch country.status {
                    case .visited: fill = Color(uiColor: .label).opacity(0.55)
                    case .wishlist: fill = .orange.opacity(0.75)
                    default: fill = Color(uiColor: .label).opacity(0.22)
                    }
                } else {
                    fill = Color(uiColor: .systemFill)
                }

                let stroke = isSel ? Color(uiColor: .label) : Color(uiColor: .systemBackground).opacity(0.75)
                let lineWidth = (isSel ? 1.2 : 0.4) / (interactiveEnabled ? currentScale : 1)

                drawCtx.fill(path, with: .color(fill), style: .init(eoFill: true))
                drawCtx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
            }

            if labelsEnabled {
                for c in shapes {
                    guard let country = countriesByISO2[c.iso2] else { continue }
                    let name = country.displayName(preferredLanguageCodes: Locale.preferredLanguages)
                    if name.isEmpty { continue }

                    let basePoint = CGPoint(
                        x: worldRect.minX + c.labelAnchor.x * worldRect.width,
                        y: worldRect.minY + c.labelAnchor.y * worldRect.height
                    )

                    let tx = (basePoint.x - camCenter.x) * currentScale + camCenter.x + offsetX
                    let ty = (basePoint.y - camCenter.y) * currentScale + camCenter.y + offsetY
                    let screenPoint = interactiveEnabled ? CGPoint(x: tx, y: ty) : basePoint

                    let f = c.focusBBoxNormalized
                    let bboxW = f.width * worldRect.width * (interactiveEnabled ? currentScale : 1)

                    let baseFont: CGFloat = 10
                    let fontScale = min(1.0, 1.0 / max(currentScale, 0.0001))
                    let fontSize = (baseFont * fontScale).clamped(8, 14)

                    let text = Text(name)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .label).opacity(0.70))

                    let resolved = ctx.resolve(text)
                    let textSize = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))

                    if bboxW >= textSize.width + 5 {
                        ctx.draw(resolved, at: screenPoint, anchor: .center)
                    }
                }
            }
        }
    }

    private func scaledPath(_ cgPath: CGPath, into rect: CGRect) -> Path {
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)
        return Path(cgPath.copy(using: &t) ?? cgPath)
    }
}

// MARK: - UIKit gesture bridge

struct MapLikeGestureView: UIViewRepresentable {
    var onPanBegan: () -> Void
    var onPanChanged: (CGSize) -> Void
    var onPanEnded: (CGPoint) -> Void
    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.minimumNumberOfTouches = 1
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator

        tap.require(toFail: doubleTap)

        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(pinch)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(doubleTap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPanBegan: onPanBegan,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded,
            onPinchBegan: onPinchBegan,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded,
            onDoubleTap: onDoubleTap,
            onTap: onTap
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPanBegan: () -> Void
        var onPanChanged: (CGSize) -> Void
        var onPanEnded: (CGPoint) -> Void
        var onPinchBegan: () -> Void
        var onPinchChanged: (CGFloat, CGPoint) -> Void
        var onPinchEnded: () -> Void
        var onDoubleTap: (CGPoint) -> Void
        var onTap: (CGPoint) -> Void

        init(
            onPanBegan: @escaping () -> Void,
            onPanChanged: @escaping (CGSize) -> Void,
            onPanEnded: @escaping (CGPoint) -> Void,
            onPinchBegan: @escaping () -> Void,
            onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
            onPinchEnded: @escaping () -> Void,
            onDoubleTap: @escaping (CGPoint) -> Void,
            onTap: @escaping (CGPoint) -> Void
        ) {
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPinchBegan = onPinchBegan
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
            self.onDoubleTap = onDoubleTap
            self.onTap = onTap
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began:
                onPanBegan()
            case .changed:
                let t = g.translation(in: v)
                onPanChanged(CGSize(width: t.x, height: t.y))
                g.setTranslation(.zero, in: v)
            case .ended, .cancelled, .failed:
                let vel = g.velocity(in: v)
                onPanEnded(CGPoint(x: vel.x, y: vel.y))
            default:
                break
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began:
                onPinchBegan()
            case .changed:
                let center = g.location(in: v)
                onPinchChanged(g.scale, center)
                g.scale = 1
            case .ended, .cancelled, .failed:
                onPinchEnded()
            default:
                break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            onTap(g.location(in: v))
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            onDoubleTap(g.location(in: v))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - GeoJSON Store

final class CountriesGeoJSONStore {
    static func load(
        resource: String = "countries",
        iso3ToIso2: [String: String],
        nameToIso2: [String: String],
        projectionMode: StaticCountriesMapView.ProjectionMode
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
                iso2 = rawName.flatMap { nameToIso2[$0] }
            }

            guard let iso2, iso2.count == 2 else { continue }

            let built = PathBuilder.makePathAndAnchors(from: f.geometry, projectionMode: projectionMode, iso2: iso2)
            result.append(RenderCountry(id: iso2, iso2: iso2, path: built.path, labelAnchor: built.labelAnchor, focusBBoxNormalized: built.focusBBox))
        }

        return result
    }
}

// MARK: - Projection + Path building

enum Projection {
    static func project(lon: Double, lat: Double, mode: StaticCountriesMapView.ProjectionMode) -> CGPoint {
        switch mode {
        case .plateCarree:
            let x = (lon + 180.0) / 360.0
            let y = (90.0 - lat) / 180.0
            return CGPoint(x: x, y: y)

        case .webMercator:
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
        let labelAnchor: CGPoint
        let focusBBox: CGRect
    }

    struct Candidate {
        let area: Double
        let centroid: CGPoint
        let bbox: CGRect
    }

    static func makePathAndAnchors(from geometry: GeoJSON.Geometry,
                                   projectionMode: StaticCountriesMapView.ProjectionMode,
                                   iso2: String) -> Built {

        let path = CGMutablePath()
        var candidates: [Candidate] = []

        func addRingToPath(_ ring: [[Double]]) {
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
            let (aSigned, c) = polygonAreaAndCentroid(pts)
            let area = abs(aSigned)
            guard area > 0, c.x.isFinite, c.y.isFinite else { return }

            let bbox = bboxPoints(pts)
            guard bbox.width > 0, bbox.height > 0 else { return }

            candidates.append(Candidate(area: area, centroid: c, bbox: bbox))
        }

        switch geometry {
        case .polygon(let rings):
            for (i, ring) in rings.enumerated() {
                addRingToPath(ring)
                if i == 0 { considerOuterRing(ring) }
            }
        case .multiPolygon(let polys):
            for poly in polys {
                for (i, ring) in poly.enumerated() {
                    addRingToPath(ring)
                    if i == 0 { considerOuterRing(ring) }
                }
            }
        }

        let bestLabel = candidates.max(by: { $0.area < $1.area })
        let labelAnchor = bestLabel?.centroid ?? CGPoint(x: 0.5, y: 0.5)

        let focusBBox = chooseFocusBBox(candidates: candidates, iso2: iso2)

        return Built(path: path, labelAnchor: labelAnchor, focusBBox: focusBBox)
    }

    private static func chooseFocusBBox(candidates: [Candidate], iso2: String) -> CGRect {
        guard !candidates.isEmpty else {
            return CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        }

        let maxArea = candidates.map(\.area).max() ?? 0
        let areaThreshold = maxArea * 0.08

        var filtered = candidates.filter { $0.area >= areaThreshold }

        if iso2 == "us" {
            let lower48 = filtered.filter { $0.centroid.y > 0.22 }
            if !lower48.isEmpty { filtered = lower48 }
        }

        let chosen = filtered.max(by: { $0.area < $1.area }) ?? candidates.max(by: { $0.area < $1.area })!
        return chosen.bbox.insetBy(dx: -0.01, dy: -0.01).clampedToUnit()
    }

    private static func bboxPoints(_ pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in pts {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite { return .zero }
        return CGRect(x: minX, y: minY, width: max(0.0001, maxX - minX), height: max(0.0001, maxY - minY))
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

// MARK: - GeoJSON decoding

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
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

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
            if let v = self[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        }
        let lower = Set(keys.map { $0.lowercased() })
        for (k, v) in self where lower.contains(k.lowercased()) {
            if let s = v.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        }
        return nil
    }
}

// MARK: - Render model

struct RenderCountry: Identifiable {
    let id: String
    let iso2: String
    let path: CGPath
    let labelAnchor: CGPoint
    let focusBBoxNormalized: CGRect
}

// MARK: - Helpers

private extension StaticCountriesMapView.ProjectionMode {
    var worldAspect: CGFloat {
        switch self {
        case .plateCarree: return 2.0
        case .webMercator: return 1.0
        }
    }
}

private extension Comparable {
    func clamped(_ minValue: Self, _ maxValue: Self) -> Self {
        min(max(self, minValue), maxValue)
    }
}

private extension CGRect {
    func clampedToUnit() -> CGRect {
        let x0 = max(0, min(1, minX))
        let y0 = max(0, min(1, minY))
        let x1 = max(0, min(1, maxX))
        let y1 = max(0, min(1, maxY))
        return CGRect(x: x0, y: y0, width: max(0.0001, x1 - x0), height: max(0.0001, y1 - y0))
    }
}
