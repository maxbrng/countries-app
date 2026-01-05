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
        case stretch
        case aspectFit
    }

    enum ProjectionMode: Equatable {
        case plateCarree
        case webMercator
    }

    // MARK: Config

    let selectionEnabled: Bool
    let interactiveEnabled: Bool
    let labelsEnabled: Bool
    let renderMode: RenderMode
    let projectionMode: ProjectionMode
    let aspectFitStartsZoomed: Bool

    /// MapKit-like extras
    let wrapHorizontally: Bool
    let rubberBanding: Bool
    let doubleTapZoomFactor: CGFloat

    /// Tap-to-focus (zoom to fit and center)
    let focusOnTap: Bool
    let focusPadding: CGFloat

    // MARK: Data

    @State private var shapes: [RenderCountry] = []
    @State private var countriesByISO2: [String: Country] = [:]
    @State private var iso3ToIso2: [String: String] = [:]
    @State private var nameToIso2: [String: String] = [:]
    @State private var selectedISO2: String?

    // MARK: Interaction state (user pan/zoom)

    @State private var baseScale: CGFloat = 1          // user scale (multiplies initialScale)
    @State private var baseOffset: CGSize = .zero      // screen points (camera translation)

    private let minUserScale: CGFloat = 1
    private let maxUserScale: CGFloat = 30

    // MARK: Deceleration

    @State private var decelTask: Task<Void, Never>?
    @State private var decelVelocity: CGPoint = .zero

    init(
        selectionEnabled: Bool = true,
        interactiveEnabled: Bool = false,
        labelsEnabled: Bool = true,
        renderMode: RenderMode = .stretch,
        projectionMode: ProjectionMode = .webMercator,
        aspectFitStartsZoomed: Bool = true,
        wrapHorizontally: Bool = false,
        rubberBanding: Bool = true,
        doubleTapZoomFactor: CGFloat = 2.0,
        focusOnTap: Bool = true,
        focusPadding: CGFloat = 24
    ) {
        self.selectionEnabled = selectionEnabled
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.renderMode = renderMode
        self.projectionMode = projectionMode
        self.aspectFitStartsZoomed = aspectFitStartsZoomed
        self.wrapHorizontally = wrapHorizontally
        self.rubberBanding = rubberBanding
        self.doubleTapZoomFactor = doubleTapZoomFactor
        self.focusOnTap = focusOnTap
        self.focusPadding = focusPadding
    }

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let viewportRect = CGRect(origin: .zero, size: viewSize)
            let worldRect = computeWorldRect(in: viewportRect, mode: renderMode, projection: projectionMode)

            let cameraScale = effectiveCameraScale(viewport: viewportRect, world: worldRect, userScaleOverride: baseScale)
            let offsetInUse = currentOffsetInUse(viewport: viewportRect, world: worldRect, cameraScale: cameraScale)

            Canvas { ctx, canvasSize in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }

                // Camera is always around VIEWPORT center (MapKit feel, fixes landscape drift).
                let camCenter = CGPoint(x: viewportRect.midX, y: viewportRect.midY)

                // 1) Draw shapes with camera transform (pan/zoom)
                var drawCtx = ctx
                if interactiveEnabled {
                    drawCtx.translateBy(x: camCenter.x, y: camCenter.y)
                    drawCtx.translateBy(x: offsetInUse.width, y: offsetInUse.height)
                    drawCtx.scaleBy(x: cameraScale, y: cameraScale)
                    drawCtx.translateBy(x: -camCenter.x, y: -camCenter.y)
                }

                for c in shapes {
                    let path = scaledPath(c.path, into: worldRect)

                    let fill = fillColor(for: c.iso2)
                    let stroke = strokeColor(for: c.iso2)
                    let lineWidth = strokeWidth(for: c.iso2) / (interactiveEnabled ? cameraScale : 1)

                    drawCtx.fill(path, with: .color(fill), style: .init(eoFill: true))
                    drawCtx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
                }

                // 2) Labels (only when interactive + selection + enabled)
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

                        // Convert anchor to screen point (apply camera transform to point only)
                        let screenPoint = interactiveEnabled
                            ? transform(point: basePoint, viewport: viewportRect, scale: cameraScale, offset: offsetInUse)
                            : basePoint

                        // Fit check uses bbox in screen space
                        let bbox = scaledPath(c.path, into: worldRect).boundingRect
                        let bboxW = bbox.width * (interactiveEnabled ? cameraScale : 1)
                        let bboxH = bbox.height * (interactiveEnabled ? cameraScale : 1)

                        // Font scaling rule:
                        // - zoom IN: do not get bigger
                        // - zoom OUT: can get a bit bigger
                        let baseFont: CGFloat = 10
                        let fontScale = min(1.0, 1.0 / max(cameraScale, 0.0001))
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
            .overlay {
                if interactiveEnabled {
                    MapLikeGestureView(
                        onPanBegan: { stopDeceleration() },
                        onPanChanged: { delta in
                            applyPan(delta: delta, viewport: viewportRect, world: worldRect)
                        },
                        onPanEnded: { velocity in
                            startDeceleration(velocity: velocity, viewport: viewportRect, world: worldRect)
                        },
                        onPinchBegan: { stopDeceleration() },
                        onPinchChanged: { scaleDelta, center in
                            applyPinch(scaleDelta: scaleDelta, center: center, viewport: viewportRect, world: worldRect)
                        },
                        onDoubleTap: { point in
                            applyDoubleTap(at: point, viewport: viewportRect, world: worldRect)
                        },
                        onTap: { point in
                            guard selectionEnabled else { return }

                            let scaleNow = effectiveCameraScale(viewport: viewportRect, world: worldRect, userScaleOverride: baseScale)
                            let offsetNow = currentOffsetInUse(viewport: viewportRect, world: worldRect, cameraScale: scaleNow)

                            // Convert tap to world coords for hit test
                            let worldPoint = untransform(point: point, viewport: viewportRect, scale: scaleNow, offset: offsetNow)

                            guard let iso2 = hitTest(point: worldPoint, in: worldRect) else {
                                selectedISO2 = nil
                                return
                            }

                            selectedISO2 = iso2

                            // NEW: focus/zoom-to-fit on tap
                            guard focusOnTap else { return }
                            focusCountry(iso2: iso2, viewport: viewportRect, world: worldRect)
                        }
                    )
                    .allowsHitTesting(true)
                }
            }
            .task(id: projectionMode) {
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
                stopDeceleration()
                baseOffset = .zero
                baseScale = 1
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
                    stopDeceleration()
                    baseScale = 1
                    baseOffset = .zero
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
            return aspectFitRect(in: viewport, aspect: projection.worldAspect)
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

    // MARK: - Camera scale

    private func effectiveCameraScale(viewport: CGRect, world: CGRect, userScaleOverride: CGFloat? = nil) -> CGFloat {
        let initialScale: CGFloat
        if renderMode == .aspectFit && aspectFitStartsZoomed {
            // Zoom so that worldRect height fills viewport height
            initialScale = (world.height > 0) ? (viewport.height / world.height) : 1
        } else {
            initialScale = 1
        }
        let user = userScaleOverride ?? baseScale
        return initialScale * user
    }

    // MARK: - Current offset used (wrap + clamp/band)

    private func currentOffsetInUse(viewport: CGRect, world: CGRect, cameraScale: CGFloat) -> CGSize {
        var off = baseOffset
        if wrapHorizontally {
            off = wrappedOffsetHorizontally(off, world: world, cameraScale: cameraScale)
        }
        if rubberBanding {
            off = rubberBandedOffset(off, viewport: viewport, world: world, cameraScale: cameraScale)
        } else {
            off = clampedOffset(viewport: viewport, world: world, cameraScale: cameraScale, offset: off)
        }
        return off
    }

    // MARK: - MapKit-like gestures

    private func stopDeceleration() {
        decelTask?.cancel()
        decelTask = nil
        decelVelocity = .zero
    }

    private func applyPan(delta: CGSize, viewport: CGRect, world: CGRect) {
        let scaleNow = effectiveCameraScale(viewport: viewport, world: world, userScaleOverride: baseScale)

        baseOffset = CGSize(width: baseOffset.width + delta.width, height: baseOffset.height + delta.height)

        if wrapHorizontally {
            baseOffset = wrappedOffsetHorizontally(baseOffset, world: world, cameraScale: scaleNow)
        }

        if rubberBanding {
            baseOffset = rubberBandedOffset(baseOffset, viewport: viewport, world: world, cameraScale: scaleNow)
        } else {
            baseOffset = clampedOffset(viewport: viewport, world: world, cameraScale: scaleNow, offset: baseOffset)
        }
    }

    private func startDeceleration(velocity: CGPoint, viewport: CGRect, world: CGRect) {
        stopDeceleration()
        decelVelocity = velocity

        decelTask = Task { @MainActor in
            var v = velocity
            let friction: CGFloat = 0.92
            let dt: CGFloat = 1.0 / 60.0

            while !Task.isCancelled {
                let delta = CGSize(width: v.x * dt, height: v.y * dt)
                applyPan(delta: delta, viewport: viewport, world: world)

                v = CGPoint(x: v.x * friction, y: v.y * friction)

                if abs(v.x) < 5, abs(v.y) < 5 { break }

                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    private func applyPinch(scaleDelta: CGFloat, center: CGPoint, viewport: CGRect, world: CGRect) {
        let oldScale = effectiveCameraScale(viewport: viewport, world: world, userScaleOverride: baseScale)

        let newUserScale = (baseScale * scaleDelta).clamped(minUserScale, maxUserScale)
        let newScale = effectiveCameraScale(viewport: viewport, world: world, userScaleOverride: newUserScale)

        // Zoom around pinch center (in VIEWPORT coordinates)
        baseOffset = zoomOffsetAroundPoint(
            offset: baseOffset,
            oldScale: oldScale,
            newScale: newScale,
            viewport: viewport,
            pinchCenter: center
        )

        baseScale = newUserScale

        if wrapHorizontally {
            baseOffset = wrappedOffsetHorizontally(baseOffset, world: world, cameraScale: newScale)
        }
        if rubberBanding {
            baseOffset = rubberBandedOffset(baseOffset, viewport: viewport, world: world, cameraScale: newScale)
        } else {
            baseOffset = clampedOffset(viewport: viewport, world: world, cameraScale: newScale, offset: baseOffset)
        }
    }

    private func applyDoubleTap(at point: CGPoint, viewport: CGRect, world: CGRect) {
        let oldScale = effectiveCameraScale(viewport: viewport, world: world, userScaleOverride: baseScale)

        let newUserScale: CGFloat = (baseScale == 30) ? min(maxUserScale, baseScale * doubleTapZoomFactor) : oldScale
        let newScale = effectiveCameraScale(viewport: viewport, world: world, userScaleOverride: newUserScale)

        baseOffset = zoomOffsetAroundPoint(
            offset: baseOffset,
            oldScale: oldScale,
            newScale: newScale,
            viewport: viewport,
            pinchCenter: point
        )
        baseScale = newUserScale

        if wrapHorizontally {
            baseOffset = wrappedOffsetHorizontally(baseOffset, world: world, cameraScale: newScale)
        }
        if rubberBanding {
            baseOffset = rubberBandedOffset(baseOffset, viewport: viewport, world: world, cameraScale: newScale)
        } else {
            baseOffset = clampedOffset(viewport: viewport, world: world, cameraScale: newScale, offset: baseOffset)
        }
    }

    /// MapKit-like: keep pinch center stable on screen (anchor zoom)
    private func zoomOffsetAroundPoint(
        offset: CGSize,
        oldScale: CGFloat,
        newScale: CGFloat,
        viewport: CGRect,
        pinchCenter: CGPoint
    ) -> CGSize {
        guard oldScale > 0 else { return offset }
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)

        // coords relative to camera center (viewport)
        let px = pinchCenter.x - camCenter.x
        let py = pinchCenter.y - camCenter.y

        let k = 1 - (newScale / oldScale)

        return CGSize(
            width: offset.width + (px - offset.width) * k,
            height: offset.height + (py - offset.height) * k
        )
    }

    // MARK: - Focus on country (zoom-to-fit & center)

    private func focusCountry(iso2: String, viewport: CGRect, world: CGRect) {
        guard let shape = shapes.first(where: { $0.iso2 == iso2 }) else { return }

        stopDeceleration()

        // Country bounds in world coordinates
        let bbox = scaledPath(shape.path, into: world).boundingRect
        guard bbox.width > 0, bbox.height > 0 else { return }

        let paddedViewport = viewport.insetBy(dx: focusPadding, dy: focusPadding)
        guard paddedViewport.width > 0, paddedViewport.height > 0 else { return }

        // Choose cameraScale so bbox fits inside viewport (with padding)
        let initialScale: CGFloat
        if renderMode == .aspectFit && aspectFitStartsZoomed {
            initialScale = (world.height > 0) ? (viewport.height / world.height) : 1
        } else {
            initialScale = 1
        }

        let targetCameraScale = min(
            paddedViewport.width / bbox.width,
            paddedViewport.height / bbox.height
        )

        // Convert to user scale (cameraScale = initialScale * userScale)
        var targetUserScale = (targetCameraScale / max(initialScale, 0.0001))
        targetUserScale = targetUserScale.clamped(minUserScale, maxUserScale)

        let finalCameraScale = initialScale * targetUserScale

        // Center bbox center in viewport center: screen(p)=center => offset = -(p-center)*scale
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let countryCenter = CGPoint(x: bbox.midX, y: bbox.midY)

        var targetOffset = CGSize(
            width: -(countryCenter.x - camCenter.x) * finalCameraScale,
            height: -(countryCenter.y - camCenter.y) * finalCameraScale
        )

        // Apply wrap/bounds behavior
        if wrapHorizontally {
            targetOffset = wrappedOffsetHorizontally(targetOffset, world: world, cameraScale: finalCameraScale)
        }
        if rubberBanding {
            targetOffset = rubberBandedOffset(targetOffset, viewport: viewport, world: world, cameraScale: finalCameraScale)
        } else {
            targetOffset = clampedOffset(viewport: viewport, world: world, cameraScale: finalCameraScale, offset: targetOffset)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            baseScale = targetUserScale
            baseOffset = targetOffset
        }
    }

    // MARK: - Rubber banding & wrap

    private func rubberBandedOffset(_ offset: CGSize, viewport: CGRect, world: CGRect, cameraScale: CGFloat) -> CGSize {
        let clamped = clampedOffset(viewport: viewport, world: world, cameraScale: cameraScale, offset: offset)
        let dx = offset.width - clamped.width
        let dy = offset.height - clamped.height

        func rubber(_ d: CGFloat) -> CGFloat {
            let c: CGFloat = 0.55
            return (d * c) / (1 + abs(d) / 300)
        }

        return CGSize(width: clamped.width + rubber(dx), height: clamped.height + rubber(dy))
    }

    private func wrappedOffsetHorizontally(_ offset: CGSize, world: CGRect, cameraScale: CGFloat) -> CGSize {
        let period = world.width * cameraScale
        guard period > 0 else { return offset }

        var x = offset.width
        x = x.truncatingRemainder(dividingBy: period)
        if x > period / 2 { x -= period }
        if x < -period / 2 { x += period }

        return CGSize(width: x, height: offset.height)
    }

    private func clampedOffset(viewport: CGRect, world: CGRect, cameraScale: CGFloat, offset: CGSize) -> CGSize {
        let contentW = world.width * cameraScale
        let contentH = world.height * cameraScale

        let maxX = max(0, (contentW - viewport.width) / 2)
        let maxY = max(0, (contentH - viewport.height) / 2)

        return CGSize(
            width: offset.width.clamped(-maxX, maxX),
            height: offset.height.clamped(-maxY, maxY)
        )
    }

    // MARK: - Transform (screen <-> world)

    private func transform(point: CGPoint, viewport: CGRect, scale: CGFloat, offset: CGSize) -> CGPoint {
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)

        var x = point.x - camCenter.x
        var y = point.y - camCenter.y

        x *= scale
        y *= scale

        x += offset.width
        y += offset.height

        x += camCenter.x
        y += camCenter.y

        return CGPoint(x: x, y: y)
    }

    private func untransform(point: CGPoint, viewport: CGRect, scale: CGFloat, offset: CGSize) -> CGPoint {
        let camCenter = CGPoint(x: viewport.midX, y: viewport.midY)

        var x = point.x - camCenter.x
        var y = point.y - camCenter.y

        x -= offset.width
        y -= offset.height

        x /= scale
        y /= scale

        x += camCenter.x
        y += camCenter.y

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

// MARK: - UIKit gesture bridge

struct MapLikeGestureView: UIViewRepresentable {
    var onPanBegan: () -> Void
    var onPanChanged: (CGSize) -> Void
    var onPanEnded: (CGPoint) -> Void // velocity points/sec

    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat, CGPoint) -> Void // scaleDelta, center

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

        var onDoubleTap: (CGPoint) -> Void
        var onTap: (CGPoint) -> Void

        init(
            onPanBegan: @escaping () -> Void,
            onPanChanged: @escaping (CGSize) -> Void,
            onPanEnded: @escaping (CGPoint) -> Void,
            onPinchBegan: @escaping () -> Void,
            onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
            onDoubleTap: @escaping (CGPoint) -> Void,
            onTap: @escaping (CGPoint) -> Void
        ) {
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPinchBegan = onPinchBegan
            self.onPinchChanged = onPinchChanged
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
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

        let bboxCenter = CGPoint(x: bestBBox.midX, y: bestBBox.midY)
        let anchor = bestBBox.contains(bestCentroid) ? bestCentroid : bboxCenter

        return Built(path: path, labelAnchor: anchor)
    }

    private static func bbox(of pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude

        for p in pts {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite { return .zero }
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
    let labelAnchor: CGPoint
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
