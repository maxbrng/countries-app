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

    /// What this map is asked to do, and therefore how much geometry it builds.
    let detail: MapDetailRequest

    /// Whether taps select a country and hit-testing runs at all.
    var selectionEnabled: Bool { detail.selectionEnabled }

    /// Whether pan, pinch and double-tap gestures are attached.
    var interactiveEnabled: Bool { detail.interactiveEnabled }

    /// Whether country labels are drawn. Effective only together with interaction
    /// and selection, see ``renderSubtree(viewport:worldRect:fitScale:)``.
    var labelsEnabled: Bool { detail.labelsEnabled }

    /// How the projected world is sized inside the viewport.
    let renderMode: FlatMapRenderMode

    /// Projection the shapes are built in.
    let projectionMode: FlatMapProjectionMode

    /// Whether ``FlatMapRenderMode/aspectFit`` starts at a fit-to-world zoom.
    let aspectFitStartsZoomed: Bool

    /// User zoom applied the first time the camera is initialized for a projection.
    let initialStartZoom: CGFloat

    /// Whether panning wraps around the antimeridian.
    let wrapsHorizontally: Bool

    /// Zoom multiplier applied per double-tap.
    let doubleTapZoomFactor: CGFloat

    /// Whether the camera frames a country when it becomes selected.
    ///
    /// Named for the selection rather than for the tap: a country is also selected from the
    /// search sheet, and the camera follows in both cases.
    let focusesSelectedCountry: Bool

    /// Inset kept free around a country when the camera frames it, in points.
    let focusPadding: CGFloat

    // MARK: - Data

    @Query private var countries: [Country]
    @Binding private var selectedCountry: Country?
    @Binding private var filter: CountryStatusFilter

    /// Where the map is looking, shared with the globe so a switch between the two keeps it.
    @Binding private var sharedFocus: MapFocus?

    @State private var viewModel = FlatMapViewModel()

    // MARK: - Selection

    /// Lowercased ISO2 code of the selection, mirrored from ``selectedCountry`` for
    /// the renderer and kept in sync in both directions.
    @State private var selectedISO2: String?

    // MARK: - Camera

    @State private var camera = FlatMapCamera()

    // MARK: - Deceleration

    @State private var decelerator = MapDecelerator()

    // MARK: - Label metrics (survives the per-frame renderer rebuild)

    @State private var labelMetrics = LabelMetricsCache()

    /// Country paths already scaled into the drawing rectangle, kept across frames.
    @State private var scaledPaths = ScaledPathCache()

    // MARK: - Layout tracking

    /// Last viewport size seen, used to tell a rotation apart from the first layout.
    @State private var lastViewportSize: CGSize = .zero

    // MARK: - Constants

    /// Camera animation timings.
    private enum MapAnimation {

        /// Frames a newly selected country.
        static let focus: Animation = .spring(response: 0.5, dampingFraction: 0.85)

        /// Fades out the highlight when the selection is cleared.
        static let deselect: Animation = .easeInOut(duration: 0.2)

        /// Settles the camera back inside its bounds after a pinch or a fling.
        static let settle: Animation = .spring(response: 0.30, dampingFraction: 0.9)

        /// Runs the double-tap zoom step.
        static let doubleTapZoom: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// Layout and camera constants.
    private enum Layout {

        /// Center of the world in normalized coordinates; the camera's reset position.
        static let worldCenter = CGPoint(x: 0.5, y: 0.5)

        /// Guards divisions against a near-zero scale.
        static let minimumScaleDivisor: CGFloat = 0.0001

        /// Exponent applied to the raw pinch delta. Below 1 it dampens the zoom step,
        /// so a fast pinch does not overshoot.
        static let pinchSmoothingExponent: CGFloat = 0.85
    }

    // MARK: - Shape variant (preview vs. full)

    /// Level of detail requested from ``FlatMapShapeCache``.
    ///
    /// - Note: The rule lives on ``MapDetailRequest`` so that a test can ask what a call site
    ///   resolves to; see ``MapPerformanceBudget``.
    private var shapeVariant: FlatMapShapeCache.Variant { detail.variant }

    /// The geometry to draw and hit-test at the current zoom.
    ///
    /// Drawing and hit-testing read the same property on purpose: a tap has to land on the
    /// shape that is actually on screen, not on a differently simplified one.
    private var currentShapes: [RenderCountryShape] {
        viewModel.shapes(forUserZoom: camera.userZoom)
    }

    // MARK: - Init

    /// Creates a FlatMapView.
    /// - Parameters:
    ///   - detail: Selection, interaction and labels, and with them the level of detail the
    ///     geometry is built at. Defaults to ``MapDetailRequest/interactive``.
    ///   - renderMode: How the world is sized inside the viewport (e.g. aspectFit).
    ///     Defaults to `.aspectFit`.
    ///   - projectionMode: Map projection used to prepare shapes. Defaults to `.webMercator`.
    ///   - aspectFitStartsZoomed: If true, starts with a fit-to-world zoom for aspectFit.
    ///     Defaults to `true`.
    ///   - wrapsHorizontally: If true, allows panning to wrap around horizontally.
    ///     Defaults to `false`.
    ///   - initialStartZoom: Initial user zoom applied on first camera initialization.
    ///     Defaults to `1.0`.
    ///   - doubleTapZoomFactor: Zoom multiplier on double-tap. Defaults to `2.0`.
    ///   - focusesSelectedCountry: If true, the camera frames a country when it becomes
    ///     selected, by tap or from the search sheet. Defaults to `true`.
    ///   - focusPadding: Padding used when focusing a country. Defaults to `24`.
    ///   - selectedCountry: External binding to the selected country.
    ///   - filter: External binding to the status filter that decides which countries
    ///     are coloured by status.
    ///   - sharedFocus: Where the map is looking, shared with the globe. Read once on appear
    ///     and written as the camera moves. Defaults to a constant `nil`, which is what a
    ///     preview wants: nothing to restore and nothing to report.
    init(
        detail: MapDetailRequest = .interactive,
        renderMode: FlatMapRenderMode = .aspectFit,
        projectionMode: FlatMapProjectionMode = .webMercator,
        aspectFitStartsZoomed: Bool = true,
        wrapsHorizontally: Bool = false,
        initialStartZoom: CGFloat = 1.0,
        doubleTapZoomFactor: CGFloat = 2.0,
        focusesSelectedCountry: Bool = true,
        focusPadding: CGFloat = 24,
        selectedCountry: Binding<Country?>,
        filter: Binding<CountryStatusFilter>,
        sharedFocus: Binding<MapFocus?> = .constant(nil)
    ) {
        self.detail = detail
        self.renderMode = renderMode
        self.projectionMode = projectionMode
        self.aspectFitStartsZoomed = aspectFitStartsZoomed
        self.initialStartZoom = initialStartZoom
        self.wrapsHorizontally = wrapsHorizontally
        self.doubleTapZoomFactor = doubleTapZoomFactor
        self.focusesSelectedCountry = focusesSelectedCountry
        self.focusPadding = focusPadding
        self._selectedCountry = selectedCountry
        self._filter = filter
        self._sharedFocus = sharedFocus

        _countries = Query()
    }

    // MARK: - Body

    /// Lays out the map, computes worldRect/fitScale, and wires up updates/lifecycle.
    var body: some View {
        
        GeometryReader { geometryProxy in
            
            // Standard calculations for the render tree
            let viewport = CGRect(origin: .zero, size: geometryProxy.size)
            let worldRect = computeWorldRect(viewport: viewport,
                                             mode: renderMode,
                                             projection: projectionMode)

            let shouldApplyZoom = renderMode == .aspectFit && aspectFitStartsZoomed && worldRect.height > 0
            let fitScale: CGFloat = shouldApplyZoom ? (viewport.height / worldRect.height) : 1.0

            renderSubtree(
                viewport: viewport,
                worldRect: worldRect,
                fitScale: fitScale
            )
            .overlay {
                // Only on the real map: the dashboard preview is decoration, and a spinner
                // flashing inside a card on every appearance says nothing worth saying. The
                // map one tap away reports and retries.
                if interactiveEnabled {
                    LoadStateOverlay(state: viewModel.loadState,
                                     loadingMessage: "Building the map…",
                                     failureMessage: Self.failureMessage) {
                        Task { await reloadDataIgnoringCache() }
                    }
                }
            }
            .onAppear {
                if lastViewportSize == .zero {
                    lastViewportSize = geometryProxy.size
                }
                camera.wrapsHorizontally = wrapsHorizontally
                camera.clamp(viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)
                restoreSharedFocus(viewport: viewport, worldRect: worldRect, fitScale: fitScale)
            }
            .onChange(of: camera) { _, _ in
                publishSharedFocus(viewport: viewport, worldRect: worldRect, fitScale: fitScale)
            }
            .onChange(of: geometryProxy.size) { _, newSize in
                guard newSize != .zero else { return }
                let oldSize = lastViewportSize
                lastViewportSize = newSize

                camera.clamp(viewport: viewport,
                             worldRect: worldRect,
                             fitScale: fitScale)

                guard oldSize != .zero, oldSize != newSize else { return }
                stopDeceleration()

                // If a country is selected during rotation, maintain focus
                if focusesSelectedCountry, let selectedISO2 {
                    focusCountry(iso2: selectedISO2,
                                 viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                }
            }
            // One task for both keys: two separate .task modifiers meant reloadData()
            // ran twice on every appearance.
            .task(id: ShapeRequest(projection: projectionMode, variant: shapeVariant)) {
                viewModel.resetCameraInitialization()
                await reloadData()
            }
            .onChange(of: selectionEnabled) { _, enabled in
                if !enabled { selectedISO2 = nil }
            }
            .onChange(of: interactiveEnabled) { _, enabled in
                guard !enabled else { return }
                stopDeceleration()
                withAnimation(.easeInOut) {
                    camera.userZoom = 1
                    camera.normalizedCenter = Layout.worldCenter
                }
            }
            .onChange(of: countries) { _, newCountries in
                // Status changes only affect colouring: never rebuild the shapes.
                viewModel.updateCountryIndex(countries: newCountries)
            }
            // Selection changes: frame the new selection, or fade the highlight out.
            .onChange(of: selectedCountry) { _, newCountry in
                guard let newCountry else {
                    withAnimation(MapAnimation.deselect) {
                        selectedISO2 = nil
                    }
                    return
                }

                // Resolve iso2
                let iso2 = viewModel.countryIndex.countriesByISO2
                    .first(where: { $0.value == newCountry })?.key ?? ""
                guard !iso2.isEmpty else { return }

                selectedISO2 = iso2

                stopDeceleration()

                guard focusesSelectedCountry else { return }

                withAnimation(MapAnimation.focus) {
                    focusCountry(iso2: iso2,
                                 viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                }
            }
        }
    }

    // MARK: - Render subtree

    /// Builds the render subtree and, if enabled, attaches the gesture overlay.
    /// - Parameters:
    ///   - viewport: The full drawing area for the map.
    ///   - worldRect: The projected world rectangle within the viewport.
    ///   - fitScale: Scale that fits worldRect into the viewport.
    /// - Returns: A view that renders the map and handles gestures when interactive.
    @ViewBuilder
    private func renderSubtree(viewport: CGRect,
                               worldRect: CGRect,
                               fitScale: CGFloat) -> some View {

        // Rendered exactly as the camera stands. Every mutation already clamps, so
        // clamping again here would only risk drawing something the hit test does
        // not agree with.
        let renderZoom = camera.userZoom
        let renderCenter = camera.normalizedCenter

        // Only adjust marking: keep rendering all shapes, but filter which countries
        // are considered for status-based styling
        let countriesByISO2ForMarking: [String: Country] = {
            switch filter {
            case .all:
                return viewModel.countryIndex.countriesByISO2
            case .visited:
                let allowed = Set(countries.filter { $0.status == .visited }.map { $0.iso2.lowercased() })
                return viewModel.countryIndex.countriesByISO2.filter { allowed.contains($0.key) }
            case .wishlist:
                let allowed = Set(countries.filter { $0.status == .wishlist }.map { $0.iso2.lowercased() })
                return viewModel.countryIndex.countriesByISO2.filter { allowed.contains($0.key) }
            }
        }()

        FlatMapRenderer(
            shapes: currentShapes,
            countriesByISO2: countriesByISO2ForMarking,
            selectedISO2: selectedISO2,
            viewport: viewport,
            worldRect: worldRect,
            fitScale: fitScale,
            userZoom: renderZoom,
            userCenter: renderCenter,
            interactiveEnabled: interactiveEnabled,
            labelsEnabled: labelsEnabled && interactiveEnabled && selectionEnabled,
            selectionEnabled: selectionEnabled,
            labelMetrics: labelMetrics,
            scaledPaths: scaledPaths
        )
        .contentShape(Rectangle())
        .overlay {
            if interactiveEnabled {
                PlatformMapGestureSurface(
                    handlers: gestureHandlers(viewport: viewport,
                                              worldRect: worldRect,
                                              fitScale: fitScale)
                )
            }
        }
    }

    // MARK: - Data loading

    /// Refreshes shapes/indices for the active projection, stops deceleration and
    /// initializes the camera once per projection.
    ///
    /// Everything the map wants to be told about a gesture, bound to the current geometry.
    ///
    /// Built per layout rather than stored: the handlers close over the viewport, the world
    /// rectangle and the fit scale, and a stored copy would keep panning the map according to
    /// the very first layout it ever had.
    ///
    /// - Parameters:
    ///   - viewport: The area the map is drawn into.
    ///   - worldRect: The projected world inside that viewport.
    ///   - fitScale: Scale applied on top of the camera's own zoom.
    /// - Returns: The handlers for ``PlatformMapGestureSurface``.
    private func gestureHandlers(viewport: CGRect,
                                 worldRect: CGRect,
                                 fitScale: CGFloat) -> MapGestureHandlers {

        MapGestureHandlers(
            onTouchDown: stopDeceleration,
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
                withAnimation(MapAnimation.settle) {
                    camera.clamp(viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                }
            },
            onDoubleTap: { point in
                withAnimation(MapAnimation.doubleTapZoom) {
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

    /// Shown when the country geometry cannot be built.
    ///
    /// Says what is missing rather than what threw: an empty ocean is not obviously a failure,
    /// which is the whole reason this message exists.
    private static let failureMessage: LocalizedStringKey =
        "The country outlines could not be built, so the map is empty."

    /// Loads the geometry again after a failure, ignoring the memo of the last request.
    private func reloadDataIgnoringCache() async {
        await viewModel.reloadShapes(projectionMode: projectionMode, variant: shapeVariant)
    }

    /// - Note: Called from a `.task(id:)` keyed on projection and variant, so it runs
    ///   once per geometry set rather than once per appearance.
    @MainActor
    private func reloadData() async {

        viewModel.updateCountryIndex(countries: countries)

        await viewModel.loadShapesIfNeeded(projectionMode: projectionMode, variant: shapeVariant)

        stopDeceleration()

        if !viewModel.didInitializeCameraForProjection {
            viewModel.markCameraInitializedForProjection()
            camera.userZoom = initialStartZoom
            camera.normalizedCenter = Layout.worldCenter
        }
    }

    // MARK: - Interaction

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

        // Must use the exact transform the renderer used, otherwise a tap while the
        // map sits in rubber-band overshoot resolves to the wrong country.
        let totalScale = fitScale * camera.userZoom

        let offset = camera.offsetFromCenter(camera.normalizedCenter,
                                             viewport: viewport,
                                             worldRect: worldRect,
                                             totalScale: totalScale)


        let worldPoint = camera.untransform(screenPoint: screenPoint,
                                            viewport: viewport,
                                            totalScale: totalScale,
                                            offset: offset)

        guard let iso2 = hitTest(worldPoint: worldPoint, in: worldRect) else {
            selectedCountry = nil
            return
        }

        selectedCountry = viewModel.countryIndex.countriesByISO2[iso2]
    }

    // MARK: - Camera framing

    /// Frames the given country by computing a target zoom/center with padding and clamping.
    /// - Parameters:
    ///   - iso2: ISO2 code of the country to focus.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for current layout.
    // MARK: - Shared focus

    /// Moves the camera to where the other renderer left off, once, when the map appears.
    ///
    /// Only the interactive map restores: a preview has no camera the user can have moved, and
    /// putting it somewhere other than the world view would be surprising.
    ///
    /// - Parameters:
    ///   - viewport: The area the map is drawn into.
    ///   - worldRect: The projected world's rect at zoom 1.
    ///   - fitScale: Scale applied before the user zoom.
    private func restoreSharedFocus(viewport: CGRect, worldRect: CGRect, fitScale: CGFloat) {

        guard interactiveEnabled,
              let sharedFocus,
              let restored = sharedFocus.flatCamera(viewport: viewport,
                                                    worldRect: worldRect,
                                                    fitScale: fitScale,
                                                    projection: projectionMode)
        else { return }

        camera.userZoom = restored.userZoom
        camera.normalizedCenter = restored.normalizedCenter
        camera.clamp(viewport: viewport, worldRect: worldRect, fitScale: fitScale)
    }

    /// Reports the camera into the shared focus so the globe can pick it up.
    ///
    /// - Parameters:
    ///   - viewport: The area the map is drawn into.
    ///   - worldRect: The projected world's rect at zoom 1.
    ///   - fitScale: Scale applied before the user zoom.
    private func publishSharedFocus(viewport: CGRect, worldRect: CGRect, fitScale: CGFloat) {

        guard interactiveEnabled,
              let reported = MapFocus.fromFlatMap(camera: camera,
                                                  viewport: viewport,
                                                  worldRect: worldRect,
                                                  fitScale: fitScale,
                                                  projection: projectionMode)
        else { return }

        sharedFocus = reported
    }

    private func focusCountry(iso2: String,
                              viewport: CGRect,
                              worldRect: CGRect,
                              fitScale: CGFloat) {
        
        guard let shape = currentShapes.first(where: { $0.iso2 == iso2 }) else { return }
        
        let focus = shape.focusBoundingBoxNormalized
        
        guard focus.width > 0, focus.height > 0 else { return }

        let paddedViewport = viewport.insetBy(dx: focusPadding, dy: focusPadding)
        
        guard paddedViewport.width > 0, paddedViewport.height > 0 else { return }

        let widthScale = paddedViewport.width / (focus.width * worldRect.width)
        let heightScale = paddedViewport.height / (focus.height * worldRect.height)
        let targetCameraScale = min(widthScale, heightScale)
        let targetUserZoom = targetCameraScale / max(fitScale, Layout.minimumScaleDivisor)

        camera.userZoom = targetUserZoom.clamped(camera.minimumUserZoom(viewport: viewport,
                                                                       worldRect: worldRect,
                                                                       fitScale: fitScale),
                                                 camera.maxUserZoom)

        let totalScale = fitScale * camera.userZoom
        
        var targetCenterX = focus.midX
        
        // landscape shift of center
        if viewport.width > viewport.height {
            
            let screenShiftRatio: CGFloat = 0.15
            let screenPixelShift = viewport.width * screenShiftRatio
            
            // Conversion: pixels -> normalized world coordinates (0.0 to 1.0)
            // Formula: pixels / (world width * current zoom)
            let normalizedShift = screenPixelShift / (worldRect.width * totalScale)
            
            targetCenterX -= normalizedShift
        }
        
        camera.normalizedCenter = camera.clampCenter(CGPoint(x: targetCenterX, y: focus.midY),
                                                     viewport: viewport,
                                                     worldRect: worldRect,
                                                     totalScale: totalScale)
    }

    /// Applies a pan delta to update the camera center while respecting clamping/wrapping.
    /// - Parameters:
    ///   - delta: Translation of this gesture step, in points.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for the current layout.
    private func applyPan(delta: CGSize,
                          viewport: CGRect,
                          worldRect: CGRect,
                          fitScale: CGFloat) {
        
        let totalScale = fitScale * camera.userZoom

        // The camera is kept inside the bounds at all times, so the current centre
        // needs no clamping here, only the result does.
        let currentOffset = camera.offsetFromCenter(camera.normalizedCenter,
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
    /// - Parameters:
    ///   - scaleDelta: Relative scale change of this gesture step.
    ///   - pinchCenter: Gesture center in view coordinates, held visually fixed.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for the current layout.
    private func applyPinch(scaleDelta: CGFloat,
                            pinchCenter: CGPoint,
                            viewport: CGRect,
                            worldRect: CGRect,
                            fitScale: CGFloat) {
        
        let minUser = camera.minimumUserZoom(viewport: viewport,
                                             worldRect: worldRect,
                                             fitScale: fitScale)

        let oldTotalScale = fitScale * camera.userZoom
        let smoothDelta = pow(scaleDelta, Layout.pinchSmoothingExponent)

        let newUserZoom = (camera.userZoom * smoothDelta).clamped(minUser, camera.maxUserZoom)
        let newTotalScale = fitScale * newUserZoom

        let currentOffset = camera.offsetFromCenter(camera.normalizedCenter,
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
    /// - Parameters:
    ///   - screenPoint: Tap location in view coordinates, held visually fixed.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for the current layout.
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

    // MARK: - Deceleration

    /// Cancels any ongoing inertial scroll.
    private func stopDeceleration() {
        decelerator.stop()
    }

    /// Starts inertial scrolling after a pan ends, then springs back inside the
    /// bounds if the fling ended past them.
    /// - Parameters:
    ///   - velocity: Ending pan velocity in points/second.
    ///   - viewport: The map's drawing area.
    ///   - worldRect: The projected world rectangle.
    ///   - fitScale: Base fit scale for the current layout.
    private func startDeceleration(velocity: CGPoint,
                                   viewport: CGRect,
                                   worldRect: CGRect,
                                   fitScale: CGFloat) {

        decelerator.start(
            velocity: velocity,
            onStep: { delta in
                applyPan(delta: delta,
                         viewport: viewport,
                         worldRect: worldRect,
                         fitScale: fitScale)
            },
            onFinish: {
                withAnimation(MapAnimation.settle) {
                    camera.clamp(viewport: viewport,
                                 worldRect: worldRect,
                                 fitScale: fitScale)
                }
            }
        )
    }

    // MARK: - Layout

    /// Computes the world rectangle within the viewport. For .stretch, returns the viewport;
    /// for aspect-preserving modes, centers letterboxed content using the projection's aspect.
    /// - Parameters:
    ///   - viewport: The full drawing area for the map.
    ///   - mode: How the world is sized inside the viewport.
    ///   - projection: Projection whose ``FlatMapProjectionMode/worldAspect`` is honoured.
    /// - Returns: The rectangle the projected world occupies inside the viewport.
    private func computeWorldRect(viewport: CGRect,
                                  mode: FlatMapRenderMode,
                                  projection: FlatMapProjectionMode) -> CGRect {

        if mode == .stretch { return viewport }

        let aspect = projection.worldAspect
        let size = viewport.size
        let viewAspect = size.width / size.height

        // Wider than the world: letterbox left and right, otherwise top and bottom.
        if viewAspect > aspect {

            let worldWidth = size.height * aspect

            return CGRect(x: (size.width - worldWidth) / 2,
                          y: 0, width: worldWidth, height: size.height)
        }

        let worldHeight = size.width / aspect

        return CGRect(x: 0,
                      y: (size.height - worldHeight) / 2,
                      width: size.width,
                      height: worldHeight)
    }

    // MARK: - Hit testing

    /// Point-in-polygon hit test (topmost-first). Returns the hit ISO2 code.
    ///
    /// The paths live in normalized 0...1 space, so instead of transforming every
    /// path into world space, which copied up to 236 CGPaths per tap, the tapped
    /// point is transformed once into that space, and each shape's bounds reject
    /// the vast majority before the expensive containment test runs.
    ///
    /// - Parameters:
    ///   - worldPoint: Tap location in world coordinates.
    ///   - worldRect: The projected world rectangle the shapes are drawn into.
    /// - Returns: The lowercased ISO2 code of the topmost shape containing the point,
    ///   or `nil` when the tap hits no country.
    private func hitTest(worldPoint: CGPoint,
                         in worldRect: CGRect) -> String? {

        guard worldRect.width > 0, worldRect.height > 0 else { return nil }

        let normalizedPoint = CGPoint(
            x: (worldPoint.x - worldRect.minX) / worldRect.width,
            y: (worldPoint.y - worldRect.minY) / worldRect.height
        )

        for shape in currentShapes.reversed() {
            guard shape.boundsNormalized.contains(normalizedPoint) else { continue }
            if shape.path.contains(normalizedPoint, using: .evenOdd) {
                return shape.iso2
            }
        }
        return nil
    }
}

