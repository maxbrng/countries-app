//
//  FlatMapView.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import SwiftData
import Observation

/// FlatMapView renders an interactive flat world map using precomputed country shapes.
///
/// Responsibilities:
/// - Layout the projected world into the available viewport
/// - Manage camera state (zoom, center, clamping, optional horizontal wrap)
/// - Handle gestures (pan, pinch, double-tap) and selection/focus
/// - Delegate data loading and drawing to the view model and renderer
///
/// Notes:
/// - Heavy computation (shape loading, camera math helpers, drawing) lives in
///   FlatMapViewModel, FlatMapCamera, and FlatMapRenderer.
struct FlatMapView: View {

    // MARK: - Configuration

    let selectionEnabled: Bool
    let interactiveEnabled: Bool
    let labelsEnabled: Bool
    let renderMode: FlatMapRenderMode
    let projectionMode: FlatMapProjectionMode
    let aspectFitStartsZoomed: Bool
    let initialStartZoom: CGFloat

    let wrapsHorizontally: Bool
    let doubleTapZoomFactor: CGFloat
    let focusOnTap: Bool
    let focusPadding: CGFloat

    let hardReloadOnRotation: Bool

    // MARK: - Data

    @Query private var countries: [Country]
    @Binding private var selectedCountry: Country?

    @State private var viewModel = FlatMapViewModel()

    // MARK: - Selection

    @State private var selectedISO2: String?

    // MARK: - Camera

    @State private var camera = FlatMapCamera()

    // MARK: - Deceleration

    @State private var decelerationTask: Task<Void, Never>?

    // MARK: - Reload

    @State private var renderTreeReloadToken: Int = 0
    @State private var lastViewportSize: CGSize = .zero

    /// Creates a FlatMapView.
    /// - Parameters:
    ///   - selectionEnabled: Enable/disable selection + hit-testing.
    ///   - interactiveEnabled: Enable/disable gestures.
    ///   - labelsEnabled: Show labels (effective only if interaction + selection are enabled).
    ///   - renderMode: How the world is sized inside the viewport (e.g. aspectFit).
    ///   - projectionMode: Map projection used to prepare shapes.
    ///   - aspectFitStartsZoomed: If true, starts with a fit-to-world zoom for aspectFit.
    ///   - wrapsHorizontally: If true, allows panning to wrap around horizontally.
    ///   - initialStartZoom: Initial user zoom applied on first camera initialization.
    ///   - doubleTapZoomFactor: Zoom multiplier on double-tap.
    ///   - focusOnTap: If true, tapping a country focuses the camera on it.
    ///   - focusPadding: Padding used when focusing a country.
    ///   - hardReloadOnRotation: Force subtree reload on size changes (e.g. rotation).
    ///   - selectedCountry: External binding to the selected country.
    init(
        selectionEnabled: Bool = true,
        interactiveEnabled: Bool = false,
        labelsEnabled: Bool = true,
        renderMode: FlatMapRenderMode = .aspectFit,
        projectionMode: FlatMapProjectionMode = .webMercator,
        aspectFitStartsZoomed: Bool = true,
        wrapsHorizontally: Bool = false,
        initialStartZoom: CGFloat = 1.0,
        doubleTapZoomFactor: CGFloat = 2.0,
        focusOnTap: Bool = true,
        focusPadding: CGFloat = 24,
        hardReloadOnRotation: Bool = true,
        selectedCountry: Binding<Country?>
    ) {
        self.selectionEnabled = selectionEnabled
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.renderMode = renderMode
        self.projectionMode = projectionMode
        self.aspectFitStartsZoomed = aspectFitStartsZoomed
        self.initialStartZoom = initialStartZoom
        self.wrapsHorizontally = wrapsHorizontally
        self.doubleTapZoomFactor = doubleTapZoomFactor
        self.focusOnTap = focusOnTap
        self.focusPadding = focusPadding
        self.hardReloadOnRotation = hardReloadOnRotation
        self._selectedCountry = selectedCountry

        _countries = Query()
    }

    /// Lays out the map, computes worldRect/fitScale, and wires up updates/lifecycle.
    var body: some View {
        
        GeometryReader { geometryProxy in
            
            let viewport = CGRect(origin: .zero, size: geometryProxy.size)
            let worldRect = computeWorldRect(viewport: viewport,
                                             mode: renderMode,
                                             projection: projectionMode)

            let shouldApplyZoom = renderMode == .aspectFit && aspectFitStartsZoomed && worldRect.height > 0
            let fitScale: CGFloat = shouldApplyZoom ? (viewport.height / worldRect.height) : 1.0

            let minUserZoom = camera.minimumUserZoom(viewport: viewport,
                                                     worldRect: worldRect,
                                                     fitScale: fitScale)

            renderSubtree(
                viewport: viewport,
                worldRect: worldRect,
                fitScale: fitScale,
                minUserZoom: minUserZoom
            )
            .id(renderTreeReloadToken)
            .onAppear {
                if lastViewportSize == .zero {
                    lastViewportSize = geometryProxy.size
                }
                camera.wrapsHorizontally = wrapsHorizontally
                camera.clamp(viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)
            }
            .onChange(of: geometryProxy.size) { _, newSize in
                guard newSize != .zero else { return }
                let oldSize = lastViewportSize
                lastViewportSize = newSize

                camera.clamp(viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)

                guard hardReloadOnRotation else { return }
                guard oldSize != .zero, oldSize != newSize else { return }
                stopDeceleration()
                
                if let selectedISO2 {
                    focusCountry(iso2: selectedISO2,
                                 viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                }
                renderTreeReloadToken &+= 1
            }
            .task(id: projectionMode) {
                viewModel.resetCameraInitialization()
                await reloadData()
            }
            .onChange(of: selectionEnabled) { _, enabled in
                if !enabled { selectedISO2 = nil }
            }
            .onChange(of: interactiveEnabled) { _, enabled in
                if !enabled {
                    stopDeceleration()
                    withAnimation(.easeInOut) {
                        camera.userZoom = 1
                        camera.normalizedCenter = CGPoint(x: 0.5, y: 0.5)
                    }
                } else if hardReloadOnRotation {
                    renderTreeReloadToken &+= 1
                }
            }
            .onChange(of: countries) { _, _ in
                // Keeps maps live when SwiftData updates.
                Task { @MainActor in await reloadData() }
            }
            .onChange(of: selectedCountry) {
                if selectedCountry == nil {
                    selectedISO2 = nil
                }
            }
        }
    }

    /// Builds the render subtree and, if enabled, attaches the gesture overlay.
    /// - Parameters:
    ///   - viewport: The full drawing area for the map.
    ///   - worldRect: The projected world rectangle within the viewport.
    ///   - fitScale: Scale that fits worldRect into the viewport.
    ///   - minUserZoom: Minimum allowed user zoom for the current layout.
    /// - Returns: A view that renders the map and handles gestures when interactive.
    @ViewBuilder
    private func renderSubtree(viewport: CGRect,
                               worldRect: CGRect,
                               fitScale: CGFloat,
                               minUserZoom: CGFloat) -> some View {
        
        let clampedZoom = camera.userZoom.clamped(minUserZoom, camera.maxUserZoom)
        let totalScale = fitScale * clampedZoom
        let clampedCenter = camera.clampCenter(camera.normalizedCenter,
                                               viewport: viewport,
                                               worldRect: worldRect,
                                               totalScale: totalScale)

        FlatMapRenderer(
            shapes: viewModel.shapes,
            countriesByISO2: viewModel.countryIndex.countriesByISO2,
            selectedISO2: selectedISO2,
            viewport: viewport,
            worldRect: worldRect,
            fitScale: fitScale,
            userZoom: clampedZoom,
            userCenter: clampedCenter,
            interactiveEnabled: interactiveEnabled,
            labelsEnabled: labelsEnabled && interactiveEnabled && selectionEnabled,
            selectionEnabled: selectionEnabled
        )
        .contentShape(Rectangle())
        .overlay {
            if interactiveEnabled {
                MapGestureOverlay(
                    onPanBegan: stopDeceleration,
                    onPanChanged: { panDelta in
                        applyPan(delta: panDelta,
                                 viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                    },
                    onPanEnded: { velocity in
                        startDeceleration(velocity: velocity,
                                          viewport: viewport,
                                          worldRect: worldRect,
                                          fitScale: fitScale)
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                            camera.clamp(viewport: viewport,
                                         worldRect: worldRect,
                                         fitScale: fitScale)
                        }
                    },
                    onPinchBegan: stopDeceleration,
                    onPinchChanged: { scaleDelta, center in
                        applyPinch(scaleDelta: scaleDelta,
                                   pinchCenter: center,
                                   viewport: viewport,
                                   worldRect: worldRect,
                                   fitScale: fitScale)
                    },
                    onPinchEnded: {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                            camera.clamp(viewport: viewport,
                                         worldRect: worldRect,
                                         fitScale: fitScale)
                        }
                    },
                    onDoubleTap: { point in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            applyDoubleTap(at: point,
                                           viewport: viewport,
                                           worldRect: worldRect,
                                           fitScale: fitScale)
                            camera.clamp(viewport: viewport,
                                         worldRect: worldRect,
                                         fitScale: fitScale)
                        }
                    },
                    onTap: { point in
                        handleTap(at: point,
                                  viewport: viewport,
                                  worldRect: worldRect,
                                  fitScale: fitScale)
                    }
                )
            }
        }
    }

    /// Refreshes shapes/indices for the active projection, stops deceleration, and
    /// initializes the camera once per projection. Triggers a subtree reload if requested.
    @MainActor
    private func reloadData() async {
        
        viewModel.updateCountryIndex(countries: countries)
        
        await viewModel.loadShapesIfNeeded(projectionMode: projectionMode)

        stopDeceleration()

        if !viewModel.didInitializeCameraForProjection {
            
            viewModel.markCameraInitializedForProjection()
            camera.userZoom = initialStartZoom
            camera.normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        }

        if hardReloadOnRotation {
            renderTreeReloadToken &+= 1
        }
    }

    /// Handles tap selection by hit-testing in world space and optionally focusing the camera.
    /// - Parameters:
    ///   - screenPoint: Tap location in view coordinates.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base scale used for transforms.
    private func handleTap(at screenPoint: CGPoint,
                           viewport: CGRect,
                           worldRect: CGRect,
                           fitScale: CGFloat) {
        
        guard selectionEnabled else { return }

        let minUser = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)
        
        let z = camera.userZoom.clamped(minUser, camera.maxUserZoom)
        let totalScale = fitScale * z
        let clampedCenter = camera.clampCenter(camera.normalizedCenter,
                                               viewport: viewport,
                                               worldRect: worldRect,
                                               totalScale: totalScale)

        let offset = camera.offsetFromCenter(clampedCenter,
                                             viewport: viewport,
                                             worldRect: worldRect,
                                             totalScale: totalScale)
        
        let worldPoint = camera.untransform(screenPoint: screenPoint,
                                            viewport: viewport,
                                            totalScale: totalScale,
                                            offset: offset)

        guard let iso2 = hitTest(worldPoint: worldPoint, in: worldRect) else {
            withAnimation(.easeInOut(duration: 0.2)) { selectedISO2 = nil }
            selectedCountry = nil
            return
        }

        selectedISO2 = iso2
        selectedCountry = viewModel.countryIndex.countriesByISO2[iso2]

        if focusOnTap {
            
            stopDeceleration()
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                focusCountry(iso2: iso2,
                             viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)
            }
        }
    }

    /// Frames the given country by computing a target zoom/center with padding and clamping.
    /// - Parameters:
    ///   - iso2: ISO2 code of the country to focus.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for current layout.
    private func focusCountry(iso2: String,
                              viewport: CGRect,
                              worldRect: CGRect,
                              fitScale: CGFloat) {
        
        guard let shape = viewModel.shapes.first(where: { $0.iso2 == iso2 }) else { return }
        
        let focus = shape.focusBoundingBoxNormalized
        
        guard focus.width > 0, focus.height > 0 else { return }

        let paddedViewport = viewport.insetBy(dx: focusPadding, dy: focusPadding)
        
        guard paddedViewport.width > 0, paddedViewport.height > 0 else { return }

        let widthScale = paddedViewport.width / (focus.width * worldRect.width)
        let heightScale = paddedViewport.height / (focus.height * worldRect.height)
        let targetCameraScale = min(widthScale, heightScale)
        let targetUserZoom = targetCameraScale / max(fitScale, 0.0001)

        camera.userZoom = targetUserZoom.clamped(camera.minimumUserZoom(viewport: viewport,
                                                                        worldRect: worldRect,
                                                                        fitScale: fitScale),
                                                 camera.maxUserZoom)

        let totalScale = fitScale * camera.userZoom
        
        var targetCenterX = focus.midX
        
        // landscape shift of center
        if viewport.width > viewport.height && selectedISO2 != nil {
            
            let screenShiftRatio: CGFloat = 0.15
            let screenPixelShift = viewport.width * screenShiftRatio
            
            // 4. Umrechnung: Pixel -> Normalisierte Welt-Koordinaten (0.0 bis 1.0)
            // Formel: Pixel / (WeltBreite * AktuellerZoom)
            let normalizedShift = screenPixelShift / (worldRect.width * totalScale)
            
            targetCenterX -= normalizedShift
        }
        
        camera.normalizedCenter = camera.clampCenter(CGPoint(x: targetCenterX, y: focus.midY),
                                                     viewport: viewport,
                                                     worldRect: worldRect,
                                                     totalScale: totalScale)
    }

    /// Applies a pan delta to update the camera center while respecting clamping/wrapping.
    private func applyPan(delta: CGSize,
                          viewport: CGRect,
                          worldRect: CGRect,
                          fitScale: CGFloat) {
        
        let minUser = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)
        camera.userZoom = camera.userZoom.clamped(minUser, camera.maxUserZoom)

        let totalScale = fitScale * camera.userZoom
        let clampedCenter = camera.clampCenter(camera.normalizedCenter,
                                               viewport: viewport,
                                               worldRect: worldRect,
                                               totalScale: totalScale)

        let currentOffset = camera.offsetFromCenter(clampedCenter,
                                                    viewport: viewport,
                                                    worldRect: worldRect,
                                                    totalScale: totalScale)
        let nextOffset = CGSize(width: currentOffset.width + delta.width, height: currentOffset.height + delta.height)

        let rawCenter = camera.centerFromOffset(nextOffset,
                                                viewport: viewport,
                                                worldRect: worldRect,
                                                totalScale: totalScale)
        
        camera.normalizedCenter = camera.clampCenter(rawCenter,
                                                     viewport: viewport,
                                                     worldRect: worldRect,
                                                     totalScale: totalScale)
    }

    /// Applies a pinch delta around a pinch center, keeping that point visually anchored.
    private func applyPinch(scaleDelta: CGFloat,
                            pinchCenter: CGPoint,
                            viewport: CGRect,
                            worldRect: CGRect,
                            fitScale: CGFloat) {
        
        let minUser = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)

        let oldTotalScale = fitScale * camera.userZoom
        let smoothDelta = pow(scaleDelta, 0.85)

        let newUserZoom = (camera.userZoom * smoothDelta).clamped(minUser, camera.maxUserZoom)
        let newTotalScale = fitScale * newUserZoom

        let clampedCenter = camera.clampCenter(camera.normalizedCenter,
                                               viewport: viewport,
                                               worldRect: worldRect,
                                               totalScale: oldTotalScale)
        
        let currentOffset = camera.offsetFromCenter(clampedCenter,
                                                    viewport: viewport,
                                                    worldRect: worldRect,
                                                    totalScale: oldTotalScale)

        let newOffset = camera.zoomOffsetAroundPoint(
            currentOffset: currentOffset,
            oldScale: oldTotalScale,
            newScale: newTotalScale,
            viewport: viewport,
            pinchCenter: pinchCenter
        )

        camera.userZoom = newUserZoom

        let rawCenter = camera.centerFromOffset(newOffset,
                                                viewport: viewport,
                                                worldRect: worldRect,
                                                totalScale: newTotalScale)
        
        camera.normalizedCenter = camera.clampCenter(rawCenter,
                                                     viewport: viewport,
                                                     worldRect: worldRect,
                                                     totalScale: newTotalScale)
    }

    /// Zooms in around the tapped point using the configured doubleTapZoomFactor.
    private func applyDoubleTap(at screenPoint: CGPoint,
                                viewport: CGRect,
                                worldRect: CGRect,
                                fitScale: CGFloat) {
        
        let minUser = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)

        let oldTotalScale = fitScale * camera.userZoom
        let targetUserZoom = (camera.userZoom * doubleTapZoomFactor).clamped(minUser, camera.maxUserZoom)
        let newTotalScale = fitScale * targetUserZoom

        let clampedCenter = camera.clampCenter(camera.normalizedCenter,
                                               viewport: viewport,
                                               worldRect: worldRect,
                                               totalScale: oldTotalScale)
        
        let currentOffset = camera.offsetFromCenter(clampedCenter,
                                                    viewport: viewport,
                                                    worldRect: worldRect,
                                                    totalScale: oldTotalScale)

        let newOffset = camera.zoomOffsetAroundPoint(
            currentOffset: currentOffset,
            oldScale: oldTotalScale,
            newScale: newTotalScale,
            viewport: viewport,
            pinchCenter: screenPoint
        )

        camera.userZoom = targetUserZoom

        let rawCenter = camera.centerFromOffset(newOffset,
                                                viewport: viewport,
                                                worldRect: worldRect,
                                                totalScale: newTotalScale)
        
        camera.normalizedCenter = camera.clampCenter(rawCenter,
                                                     viewport: viewport,
                                                     worldRect: worldRect,
                                                     totalScale: newTotalScale)
    }

    /// Cancels any ongoing inertial scroll.
    private func stopDeceleration() {
        decelerationTask?.cancel()
        decelerationTask = nil
    }

    /// Starts inertial scrolling after a pan ends, decaying velocity over time and clamping at rest.
    /// - Parameters:
    ///   - velocity: Ending pan velocity in points/second.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for the current layout.
    private func startDeceleration(velocity: CGPoint,
                                   viewport: CGRect,
                                   worldRect: CGRect,
                                   fitScale: CGFloat) {
        
        stopDeceleration()

        decelerationTask = Task { @MainActor in
            var currentVelocity = velocity

            while !Task.isCancelled {
                let dt: CGFloat = 1.0 / 60.0
                let delta = CGSize(width: currentVelocity.x * dt, height: currentVelocity.y * dt)
                
                applyPan(delta: delta,
                         viewport: viewport,
                         worldRect: worldRect,
                         fitScale: fitScale)

                currentVelocity = CGPoint(x: currentVelocity.x * 0.92, y: currentVelocity.y * 0.92)
                if abs(currentVelocity.x) < 5 && abs(currentVelocity.y) < 5 { break }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                camera.clamp(viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)
            }
        }
    }

    /// Computes the world rectangle within the viewport. For .stretch, returns the viewport;
    /// for aspect-preserving modes, centers letterboxed content using the projection's aspect.
    private func computeWorldRect(viewport: CGRect,
                                  mode: FlatMapRenderMode,
                                  projection: FlatMapProjectionMode) -> CGRect {
        
        if mode == .stretch { return viewport }

        let aspect = projection.worldAspect
        let size = viewport.size
        let viewAspect = size.width / size.height

        if viewAspect > aspect {
            
            let w = size.height * aspect
            
            return CGRect(x: (size.width - w) / 2,
                          y: 0, width: w, height: size.height)
        } else {
            
            let h = size.width / aspect
            
            return CGRect(x: 0,
                          y: (size.height - h) / 2,
                          width: size.width,
                          height: h)
        }
    }

    /// Point-in-polygon hit test in world coordinates (topmost-first). Returns the hit ISO2 code.
    private func hitTest(worldPoint: CGPoint,
                         in worldRect: CGRect) -> String? {
        
        for shape in viewModel.shapes.reversed() {
            
            var transform = CGAffineTransform(translationX: worldRect.minX,
                                              y: worldRect.minY)
                .scaledBy(x: worldRect.width,
                          y: worldRect.height)

            if shape.path.copy(using: &transform)?.contains(worldPoint, using: .evenOdd) == true {
                return shape.iso2
            }
        }
        return nil
    }
}

