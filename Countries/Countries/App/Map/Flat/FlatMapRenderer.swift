//
//  FlatMapRenderer.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import SwiftData
import CoreGraphics

/// Draws the flat world map into a single `Canvas`: one fill and stroke per country,
/// plus collision-free labels on top.
///
/// The type is `Animatable` on zoom and center, so SwiftUI drives camera animations by
/// rebuilding and redrawing this view per frame. Everything in the draw pass therefore
/// has to stay cheap: the geometry arrives pre-built as ``RenderCountryShape`` values and
/// the label sizes come from the shared ``LabelMetricsCache``.
struct FlatMapRenderer: View, Animatable {

    // MARK: - Content

    /// Pre-built country geometry in normalized world space (0...1 on both axes).
    let shapes: [RenderCountryShape]

    /// Countries eligible for status-based colouring, keyed by lowercased ISO2 code.
    /// A shape without an entry here is drawn in the neutral fill.
    let countriesByISO2: [String: Country]

    /// Lowercased ISO2 code of the selected country, or `nil` when nothing is selected.
    let selectedISO2: String?

    /// Lowercased ISO2 codes marked by the caller rather than by their stored status.
    ///
    /// Drawn as visited. The first launch needs this: nothing is written to the store until
    /// the flow is confirmed, so until then the only record of what the user has picked is
    /// the caller's own set. Empty everywhere else, where the status is the truth.
    let pendingVisitedISO2: Set<String>

    // MARK: - Layout

    /// Full drawing area of the canvas.
    let viewport: CGRect

    /// The projected world rectangle inside ``viewport``.
    let worldRect: CGRect

    /// Scale that fits ``worldRect`` into ``viewport``; multiplied by ``userZoom``.
    let fitScale: CGFloat

    // MARK: - Camera (animatable)

    /// User zoom factor on top of ``fitScale``.
    var userZoom: CGFloat

    /// Camera center in normalized world space (0...1 on both axes).
    var userCenter: CGPoint

    // MARK: - Feature flags

    /// Whether the camera transform is applied at all. A preview draws unscaled.
    let interactiveEnabled: Bool

    /// Whether country labels are drawn.
    let labelsEnabled: Bool

    /// Whether the selected country is highlighted.
    let selectionEnabled: Bool

    // MARK: - Caches

    /// Reference type on purpose: the renderer struct is rebuilt every frame, the
    /// measured label sizes must outlive it.
    let labelMetrics: LabelMetricsCache

    /// Reference type for the same reason: scaling a country's path into the drawing
    /// rectangle produces the same result on every frame, so it is done once per layout.
    let scaledPaths: ScaledPathCache

    // MARK: - Constants

    /// Line weights of the country outlines.
    ///
    /// The colours and their opacities live in ``MapPalette``, which is where they are
    /// documented with the contrast they reach. Duplicating them here once meant a colour
    /// could be changed in the palette with no effect on the map.
    private enum Style {

        /// Border width of the selected country, in points before the camera scale.
        static let selectedLineWidth: CGFloat = 1.2
        /// Border width of every other country, in points before the camera scale.
        static let lineWidth: CGFloat = 0.4
    }

    /// Thresholds and paddings of the label placement pass. All values are tuned
    /// against the real country set; changing one changes how many labels survive.
    private enum LabelLayout {

        /// Labels stay alive slightly outside the viewport so they do not pop in at
        /// the edge while panning.
        static let viewportOverscan: CGFloat = 80

        /// Label font size before the zoom compensation is applied.
        static let baseFontSize: CGFloat = 10
        /// Lower bound of the zoom-compensated font size.
        static let minimumFontSize: CGFloat = 8
        /// Upper bound of the zoom-compensated font size.
        static let maximumFontSize: CGFloat = 14
        /// Guards the font scale against dividing by a near-zero camera scale.
        static let minimumScaleDivisor: CGFloat = 0.0001

        /// Horizontal slack a country's box needs on top of the text width.
        static let textFitPaddingWidth: CGFloat = 10
        /// Vertical slack a country's box needs on top of the text height.
        static let textFitPaddingHeight: CGFloat = 8

        /// Absolute floor for the width a country's box must have to take a label.
        static let minimumBoxWidthFloor: CGFloat = 26
        /// Absolute floor for the height a country's box must have to take a label.
        static let minimumBoxHeightFloor: CGFloat = 16
        /// Absolute floor for the area a country's box must have to take a label.
        static let minimumBoxAreaFloor: CGFloat = 200
        /// How many times the text area a country's box must cover.
        static let boxToTextAreaFactor: CGFloat = 2.4

        /// Padding added around a label rect before the collision test.
        static let collisionPadding: CGFloat = 6
        /// Side length of one collision-grid cell, in points.
        static let cellSize: CGFloat = 120

        /// Smallest extent a projected rect may collapse to, so it stays testable.
        static let minimumProjectedExtent: CGFloat = 0.1

        /// Reserved capacity of the per-frame candidate list.
        static let candidateReserveCapacity = 256
        /// Reserved capacity of the per-frame collision grid.
        static let gridReserveCapacity = 256
    }

    // MARK: - Animatable

    /// Zoom and center, packed so SwiftUI can interpolate the camera.
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(userZoom, AnimatablePair(userCenter.x, userCenter.y)) }
        set {
            userZoom = newValue.first
            userCenter = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    // MARK: - Init

    /// Creates a renderer for one frame of the flat map.
    /// - Parameters:
    ///   - shapes: Pre-built geometry in normalized world space.
    ///   - countriesByISO2: Countries eligible for status colouring, keyed by lowercased ISO2.
    ///   - selectedISO2: Lowercased ISO2 code of the selected country, or `nil`.
    ///   - pendingVisitedISO2: Lowercased codes to draw as visited regardless of their status.
    ///   - viewport: Full drawing area.
    ///   - worldRect: Projected world rectangle inside the viewport.
    ///   - fitScale: Scale that fits the world into the viewport.
    ///   - userZoom: User zoom factor on top of `fitScale`.
    ///   - userCenter: Camera center in normalized world space.
    ///   - interactiveEnabled: Whether the camera transform is applied.
    ///   - labelsEnabled: Whether labels are drawn.
    ///   - selectionEnabled: Whether the selection is highlighted.
    ///   - labelMetrics: Cache that outlives the per-frame struct rebuild.
    ///   - scaledPaths: Path cache that outlives the per-frame struct rebuild.
    init(
        shapes: [RenderCountryShape],
        countriesByISO2: [String: Country],
        selectedISO2: String?,
        pendingVisitedISO2: Set<String>,
        viewport: CGRect,
        worldRect: CGRect,
        fitScale: CGFloat,
        userZoom: CGFloat,
        userCenter: CGPoint,
        interactiveEnabled: Bool,
        labelsEnabled: Bool,
        selectionEnabled: Bool,
        labelMetrics: LabelMetricsCache,
        scaledPaths: ScaledPathCache
    ) {
        self.shapes = shapes
        self.countriesByISO2 = countriesByISO2
        self.selectedISO2 = selectedISO2
        self.pendingVisitedISO2 = pendingVisitedISO2
        self.viewport = viewport
        self.worldRect = worldRect
        self.fitScale = fitScale
        self.userZoom = userZoom
        self.userCenter = userCenter
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.selectionEnabled = selectionEnabled
        self.labelMetrics = labelMetrics
        self.scaledPaths = scaledPaths
    }

    // MARK: - Body

    /// Applies the camera transform, draws every country, then the labels on top.
    var body: some View {

        Canvas { context, _ in

            guard viewport.width > 0, viewport.height > 0 else { return }

            let currentScale = fitScale * userZoom

            let cameraCenter = CGPoint(x: viewport.midX, y: viewport.midY)
            let worldPointX = worldRect.minX + userCenter.x * worldRect.width
            let worldPointY = worldRect.minY + userCenter.y * worldRect.height

            let offsetX = (cameraCenter.x - worldPointX) * currentScale
            let offsetY = (cameraCenter.y - worldPointY) * currentScale

            var drawContext = context

            if interactiveEnabled {
                drawContext.translateBy(x: cameraCenter.x + offsetX, y: cameraCenter.y + offsetY)
                drawContext.scaleBy(x: currentScale, y: currentScale)
                drawContext.translateBy(x: -cameraCenter.x, y: -cameraCenter.y)
            }

            let visibleRect = visibleDrawRect(cameraCenter: cameraCenter,
                                              currentScale: currentScale,
                                              offsetX: offsetX,
                                              offsetY: offsetY)

            for shape in shapes {
                let path = scaledPaths.path(for: shape.path, in: worldRect)

                // Off-screen countries cost nothing to skip and everything to draw: since
                // [D-05] each one carries roughly four times the points it used to, and at
                // any zoom past the world view most of them are nowhere near the viewport.
                guard path.boundingRect.intersects(visibleRect) else { continue }

                let isSelected = (selectionEnabled && selectedISO2 == shape.iso2)

                let fillColor = fill(for: shape.iso2, isSelected: isSelected)
                let strokeColor = isSelected ? MapPalette.selectionStroke
                                             : MapPalette.interiorBorder

                // Divided by the camera scale so the border keeps a constant
                // on-screen width at every zoom level.
                let baseLineWidth = isSelected ? Style.selectedLineWidth : Style.lineWidth
                let lineWidth = baseLineWidth / (interactiveEnabled ? currentScale : 1)

                drawContext.fill(path, with: .color(fillColor), style: .init(eoFill: true))
                drawContext.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
            }

            if labelsEnabled {
                drawLabels(
                    in: context,
                    cameraCenter: cameraCenter,
                    currentScale: currentScale,
                    offsetX: offsetX,
                    offsetY: offsetY
                )
            }
        }
    }

    // MARK: - Fill

    /// Resolves the fill colour of one country from its tracking status.
    /// - Parameters:
    ///   - iso2: Lowercased ISO2 code of the shape being drawn.
    ///   - isSelected: Whether this country is the selected one.
    /// - Returns: The status colour, or the neutral system fill when the country is
    ///   not part of ``countriesByISO2`` (unknown, or filtered out).
    private func fill(for iso2: String, isSelected: Bool) -> Color {

        guard let country = countriesByISO2[iso2] else { return MapPalette.unknownLandFill }

        switch country.status {
        case .visited:
            return MapPalette.visitedFill
        case .wishlist:
            return MapPalette.wishlistFill
        default:
            return MapPalette.neutralLandFill
        }
    }

    // MARK: - Visible area

    /// The part of the drawing space the viewport currently shows.
    ///
    /// The canvas carries the camera transform, so a country's bounding box is in that
    /// transformed space and can be far larger than the screen. Intersecting with this is what
    /// makes the work proportional to what is on screen instead of to how far the user has
    /// zoomed in.
    ///
    /// - Parameters:
    ///   - cameraCenter: Centre of the viewport, the fixed point of the scale.
    ///   - currentScale: Fit scale times user zoom.
    ///   - offsetX: Horizontal camera offset already applied to the context.
    ///   - offsetY: Vertical camera offset already applied to the context.
    /// - Returns: The visible rectangle, in the space the canvas draws in.
    private func visibleDrawRect(cameraCenter: CGPoint,
                                 currentScale: CGFloat,
                                 offsetX: CGFloat,
                                 offsetY: CGFloat) -> CGRect {

        guard interactiveEnabled, currentScale > 0 else { return viewport }

        let translatedX = cameraCenter.x + offsetX
        let translatedY = cameraCenter.y + offsetY

        let originX = cameraCenter.x + (viewport.minX - translatedX) / currentScale
        let originY = cameraCenter.y + (viewport.minY - translatedY) / currentScale

        return CGRect(x: originX,
                      y: originY,
                      width: viewport.width / currentScale,
                      height: viewport.height / currentScale)
    }

    // MARK: - Labels (collision-free)

    /// Draws one label per country that both fits its shape and does not collide with
    /// an already placed label.
    ///
    /// Three passes: collect candidates that pass the fit test, sort them by on-screen
    /// area so the largest country wins a contested spot, then place them against a
    /// uniform grid of buckets that keeps the collision test local instead of comparing
    /// every rect against every other one.
    ///
    /// - Parameters:
    ///   - context: The unscaled canvas context. Labels are positioned in screen space
    ///     by hand so they keep their font size regardless of the camera scale.
    ///   - cameraCenter: Center of the viewport, the fixed point of the camera transform.
    ///   - currentScale: `fitScale` times `userZoom`.
    ///   - offsetX: Horizontal camera offset in points.
    ///   - offsetY: Vertical camera offset in points.
    private func drawLabels(in context: GraphicsContext,
                            cameraCenter: CGPoint,
                            currentScale: CGFloat,
                            offsetX: CGFloat,
                            offsetY: CGFloat) {

        /// One label that passed the fit test and is waiting for the collision pass.
        struct Candidate {
            let iso2: String
            let name: String
            let fontSize: CGFloat
            let screenPoint: CGPoint
            let textSize: CGSize
            let score: CGFloat
            let rect: CGRect
        }

        /// Applies the camera transform by hand; a preview draws in world space already.
        func worldToScreen(_ worldPoint: CGPoint) -> CGPoint {

            let transformedX = (worldPoint.x - cameraCenter.x) * currentScale + cameraCenter.x + offsetX
            let transformedY = (worldPoint.y - cameraCenter.y) * currentScale + cameraCenter.y + offsetY

            return interactiveEnabled ? CGPoint(x: transformedX, y: transformedY) : worldPoint
        }

        /// Projects all four corners, since the transform may flip or offset the rect.
        func worldRectToScreenRect(_ rect: CGRect) -> CGRect {

            let topLeft = worldToScreen(CGPoint(x: rect.minX, y: rect.minY))
            let topRight = worldToScreen(CGPoint(x: rect.maxX, y: rect.minY))
            let bottomLeft = worldToScreen(CGPoint(x: rect.minX, y: rect.maxY))
            let bottomRight = worldToScreen(CGPoint(x: rect.maxX, y: rect.maxY))

            let minX = min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
            let maxX = max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
            let minY = min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
            let maxY = max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)

            return CGRect(x: minX,
                          y: minY,
                          width: max(LabelLayout.minimumProjectedExtent, maxX - minX),
                          height: max(LabelLayout.minimumProjectedExtent, maxY - minY))
        }

        let viewportExpanded = viewport.insetBy(dx: -LabelLayout.viewportOverscan,
                                                dy: -LabelLayout.viewportOverscan)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(LabelLayout.candidateReserveCapacity)

        for shape in shapes {

            guard let country = countriesByISO2[shape.iso2] else { continue }

            let name = country.nameEnglish
            guard !name.isEmpty else { continue }

            let anchorWorld = CGPoint(
                x: worldRect.minX + shape.labelAnchor.x * worldRect.width,
                y: worldRect.minY + shape.labelAnchor.y * worldRect.height
            )
            let anchorScreen = worldToScreen(anchorWorld)

            let focus = shape.focusBoundingBoxNormalized

            let focusWorld = CGRect(
                x: worldRect.minX + focus.minX * worldRect.width,
                y: worldRect.minY + focus.minY * worldRect.height,
                width: focus.width * worldRect.width,
                height: focus.height * worldRect.height
            )
            let focusScreenRect = worldRectToScreenRect(focusWorld)

            guard focusScreenRect.intersects(viewportExpanded) else { continue }

            let fontScale = min(1.0, 1.0 / max(currentScale, LabelLayout.minimumScaleDivisor))
            // Rounded so the metrics cache hits instead of missing on every frame.
            let fontSize = (LabelLayout.baseFontSize * fontScale)
                .clamped(LabelLayout.minimumFontSize, LabelLayout.maximumFontSize)
                .rounded()

            // Measured through UIKit and cached across frames. The SwiftUI Text is
            // resolved further down, only for labels that actually get drawn.
            let textSize = labelMetrics.size(for: name, fontSize: fontSize)

            let minimumBoxWidth: CGFloat = max(LabelLayout.minimumBoxWidthFloor,
                                               textSize.width + LabelLayout.textFitPaddingWidth)
            let minimumBoxHeight: CGFloat = max(LabelLayout.minimumBoxHeightFloor,
                                                textSize.height + LabelLayout.textFitPaddingHeight)
            let textArea = textSize.width * textSize.height
            let minimumArea: CGFloat = max(LabelLayout.minimumBoxAreaFloor,
                                           textArea * LabelLayout.boxToTextAreaFactor)

            let bboxArea = focusScreenRect.width * focusScreenRect.height

            guard focusScreenRect.width >= minimumBoxWidth,
                  focusScreenRect.height >= minimumBoxHeight,
                  bboxArea >= minimumArea
            else { continue }

            let collisionPadding = LabelLayout.collisionPadding
            let labelRect = CGRect(
                x: anchorScreen.x - textSize.width * 0.5 - collisionPadding,
                y: anchorScreen.y - textSize.height * 0.5 - collisionPadding,
                width: textSize.width + collisionPadding * 2,
                height: textSize.height + collisionPadding * 2
            )
            guard labelRect.intersects(viewportExpanded) else { continue }

            candidates.append(.init(
                iso2: shape.iso2,
                name: name,
                fontSize: fontSize,
                screenPoint: anchorScreen,
                textSize: textSize,
                score: bboxArea,
                rect: labelRect
            ))
        }

        // Largest country first, so it keeps its label when two labels overlap.
        candidates.sort { $0.score > $1.score }

        /// Bucket coordinate in the uniform collision grid.
        struct CellKey: Hashable { let x: Int; let y: Int }
        let cellSize = LabelLayout.cellSize
        var grid: [CellKey: [CGRect]] = [:]
        grid.reserveCapacity(LabelLayout.gridReserveCapacity)

        /// Buckets a rect covers, as (minX, maxX, minY, maxY) cell indices.
        func cellRange(for rect: CGRect) -> (Int, Int, Int, Int) {
            let minCellX = Int(floor(rect.minX / cellSize))
            let maxCellX = Int(floor(rect.maxX / cellSize))
            let minCellY = Int(floor(rect.minY / cellSize))
            let maxCellY = Int(floor(rect.maxY / cellSize))
            return (minCellX, maxCellX, minCellY, maxCellY)
        }

        /// Whether the rect overlaps a label that was already placed.
        func intersectsPlaced(_ rect: CGRect) -> Bool {
            let (minCellX, maxCellX, minCellY, maxCellY) = cellRange(for: rect)
            for cellY in minCellY...maxCellY {
                for cellX in minCellX...maxCellX {
                    let key = CellKey(x: cellX, y: cellY)
                    guard let placedRects = grid[key] else { continue }
                    for placedRect in placedRects where placedRect.intersects(rect) {
                        return true
                    }
                }
            }
            return false
        }

        /// Registers a placed label in every bucket it touches.
        func insertPlaced(_ rect: CGRect) {

            let (minCellX, maxCellX, minCellY, maxCellY) = cellRange(for: rect)

            for cellY in minCellY...maxCellY {

                for cellX in minCellX...maxCellX {
                    let key = CellKey(x: cellX, y: cellY)
                    grid[key, default: []].append(rect)
                }
            }
        }

        for candidate in candidates {

            if intersectsPlaced(candidate.rect) { continue }

            insertPlaced(candidate.rect)

            // Resolved here rather than during the scan: only labels that survive
            // the fit and collision checks are worth the text layout.
            let text = Text(candidate.name)
                .font(.system(size: candidate.fontSize, weight: .semibold))
                .foregroundStyle(MapPalette.labelText)

            context.draw(context.resolve(text),
                         at: candidate.screenPoint,
                         anchor: .center)
        }
    }

}
