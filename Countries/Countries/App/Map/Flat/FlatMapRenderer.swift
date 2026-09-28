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

    /// Whether marked countries carry their ``StatusHatching`` texture.
    ///
    /// Off for the dashboard preview: at that size the hatch would read as noise, and the
    /// preview carries no status legend to read it against.
    let hatchingEnabled: Bool

    // MARK: - Caches

    /// Reference type on purpose: the renderer struct is rebuilt every frame, the
    /// measured label sizes must outlive it.
    let labelMetrics: LabelMetricsCache

    /// Reference type for the same reason: scaling a country's path into the drawing
    /// rectangle produces the same result on every frame, so it is done once per layout.
    let scaledPaths: ScaledPathCache

    // MARK: - Constants

    /// Thresholds and paddings of the label placement pass. All values are tuned
    /// against the real country set; changing one changes how many labels survive.
    private enum LabelLayout {

        /// Labels stay alive slightly outside the viewport so they do not pop in at
        /// the edge while panning.
        static let viewportOverscan: CGFloat = 80

        /// Fraction of the viewport a country's box must cover before it is allowed a label.
        ///
        /// This is what keeps the world view clean: at the minimum zoom even Russia covers
        /// far less than this, so nothing is drawn, and names appear as the map is zoomed in
        /// and countries grow on screen. Every native map behaves this way; the previous
        /// version had only an absolute size floor, which the large countries passed at every
        /// zoom level including the smallest.
        static let minimumViewportCoverage: CGFloat = 0.025

        /// How much larger than the viewport the whole world must be before any label is drawn.
        ///
        /// At the minimum zoom the world exactly fills the viewport, so this draws nothing at
        /// all there - which is the ask: a world view carries no names. Mercator alone would
        /// not give that, because it inflates Greenland enough to pass any area test.
        static let minimumWorldToViewportScale: CGFloat = 1.5

        /// Size every label is drawn at, in screen points.
        ///
        /// - Note: Constant on purpose. Labels are drawn in screen space, so they never grow
        ///   with the camera and never needed a compensation. The earlier `baseFontSize /
        ///   currentScale` shrank them instead, and the 8 pt floor was reached at about 1.25x,
        ///   which is why a zoomed-in map read worse than a zoomed-out one.
        static let fontSize: CGFloat = 11

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
    ///   - viewport: Full drawing area.
    ///   - worldRect: Projected world rectangle inside the viewport.
    ///   - fitScale: Scale that fits the world into the viewport.
    ///   - userZoom: User zoom factor on top of `fitScale`.
    ///   - userCenter: Camera center in normalized world space.
    ///   - interactiveEnabled: Whether the camera transform is applied.
    ///   - labelsEnabled: Whether labels are drawn.
    ///   - selectionEnabled: Whether the selection is highlighted.
    ///   - hatchingEnabled: Whether marked countries are hatched.
    ///   - labelMetrics: Cache that outlives the per-frame struct rebuild.
    ///   - scaledPaths: Path cache that outlives the per-frame struct rebuild.
    init(
        shapes: [RenderCountryShape],
        countriesByISO2: [String: Country],
        selectedISO2: String?,
        viewport: CGRect,
        worldRect: CGRect,
        fitScale: CGFloat,
        userZoom: CGFloat,
        userCenter: CGPoint,
        interactiveEnabled: Bool,
        labelsEnabled: Bool,
        selectionEnabled: Bool,
        hatchingEnabled: Bool,
        labelMetrics: LabelMetricsCache,
        scaledPaths: ScaledPathCache
    ) {
        self.shapes = shapes
        self.countriesByISO2 = countriesByISO2
        self.selectedISO2 = selectedISO2
        self.viewport = viewport
        self.worldRect = worldRect
        self.fitScale = fitScale
        self.userZoom = userZoom
        self.userCenter = userCenter
        self.interactiveEnabled = interactiveEnabled
        self.labelsEnabled = labelsEnabled
        self.selectionEnabled = selectionEnabled
        self.hatchingEnabled = hatchingEnabled
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

            // Coastlines first, as a casing under the fills: along a shared border the two
            // neighbouring fills cover the stroke again, so it survives only where land meets
            // water. Drawing it after the fills instead would outline every country and turn
            // the map into a net.
            let coastlineWidth = coastlineLineWidth(currentScale: currentScale)
            let visibleDrawRect = visibleDrawRect(cameraCenter: cameraCenter,
                                                  currentScale: currentScale,
                                                  offsetX: offsetX,
                                                  offsetY: offsetY)

            for shape in shapes {
                drawContext.stroke(scaledPaths.path(for: shape.path, in: worldRect),
                                   with: .color(MapPalette.coastline),
                                   lineWidth: coastlineWidth)
            }

            for shape in shapes {
                let path = scaledPaths.path(for: shape.path, in: worldRect)
                let isSelected = (selectionEnabled && selectedISO2 == shape.iso2)

                let fillColor = fill(for: shape.iso2)
                let strokeColor = isSelected ? MapPalette.selectionStroke
                                             : MapPalette.interiorBorder

                // Divided by the camera scale so the border keeps a constant
                // on-screen width at every zoom level.
                let baseLineWidth = isSelected ? MapStrokeMetrics.selectedBorderWidth
                                               : MapStrokeMetrics.interiorBorderWidth
                let lineWidth = baseLineWidth / (interactiveEnabled ? currentScale : 1)

                drawContext.fill(path, with: .color(fillColor), style: .init(eoFill: true))

                if hatchingEnabled, let direction = hatchDirection(for: shape.iso2) {
                    drawHatching(direction,
                                 over: path,
                                 clippedTo: visibleDrawRect,
                                 currentScale: currentScale,
                                 in: drawContext)
                }

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

    // MARK: - Coastline

    /// Width of the coastline casing in the coordinate space the canvas is drawing in.
    ///
    /// Divided by the camera scale for the same reason the borders are: the canvas is scaled,
    /// the stroke should not be.
    ///
    /// - Parameter currentScale: Fit scale times user zoom, the factor the canvas is scaled by.
    /// - Returns: The line width to hand to `stroke(_:with:lineWidth:)`.
    private func coastlineLineWidth(currentScale: CGFloat) -> CGFloat {

        let onScreen = MapStrokeMetrics.coastlineWidth(forUserZoom: userZoom)
        return onScreen / (interactiveEnabled ? currentScale : 1)
    }

    // MARK: - Status hatching

    /// The part of the drawing space the viewport currently shows.
    ///
    /// The canvas carries the camera transform, so a country's bounding box is in that
    /// transformed space and can be far larger than the screen. Intersecting with this is what
    /// keeps the hatch line count bounded by what is actually visible instead of by how far
    /// the user has zoomed in.
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

    /// The hatch direction a country's status calls for, or `nil` when it carries no status.
    ///
    /// - Parameter iso2: Lowercased ISO2 code of the shape being drawn.
    private func hatchDirection(for iso2: String) -> StatusHatching.Direction? {

        switch countriesByISO2[iso2]?.status {
        case .visited: .rising
        case .wishlist: .falling
        default: nil
        }
    }

    /// Draws the hatch of one country, clipped to its own shape.
    ///
    /// - Parameters:
    ///   - direction: Which way the lines run.
    ///   - path: The country, already scaled into the drawing rectangle.
    ///   - visibleRect: What the viewport shows, in the drawing space.
    ///   - currentScale: Fit scale times user zoom, used to keep spacing and line width
    ///     constant on screen.
    ///   - context: The canvas context; a copy is clipped, so the caller's context is
    ///     untouched.
    private func drawHatching(_ direction: StatusHatching.Direction,
                              over path: Path,
                              clippedTo visibleRect: CGRect,
                              currentScale: CGFloat,
                              in context: GraphicsContext) {

        let area = path.boundingRect.intersection(visibleRect)

        guard !area.isNull, !area.isEmpty else { return }

        let cameraScale = interactiveEnabled ? currentScale : 1
        let lines = StatusHatching.path(covering: area,
                                        direction: direction,
                                        spacing: StatusHatching.spacing / cameraScale)

        var layer = context
        layer.clip(to: path, style: .init(eoFill: true))
        layer.stroke(lines,
                     with: .color(MapPalette.statusHatch),
                     lineWidth: StatusHatching.lineWidth / cameraScale)
    }

    // MARK: - Fill

    /// Resolves the fill colour of one country from its tracking status.
    ///
    /// - Note: The selection does not change the fill. It is carried by the stroke colour and
    ///   width instead, so that a selected country still shows its status.
    ///
    /// - Parameter iso2: Lowercased ISO2 code of the shape being drawn.
    /// - Returns: The status colour, or the neutral system fill when the country is
    ///   not part of ``countriesByISO2`` (unknown, or filtered out).
    private func fill(for iso2: String) -> Color {

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
            /// Natural Earth's importance, lower wins.
            let rank: Int
            /// Projected box area, the tie-breaker within one rank.
            let area: CGFloat
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

        // Nothing at all while the map is at or near its minimum zoom.
        let worldHeightOnScreen = worldRect.height * currentScale
        guard viewport.height > 0,
              worldHeightOnScreen / viewport.height >= LabelLayout.minimumWorldToViewportScale
        else { return }

        let viewportExpanded = viewport.insetBy(dx: -LabelLayout.viewportOverscan,
                                                dy: -LabelLayout.viewportOverscan)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(LabelLayout.candidateReserveCapacity)

        for shape in shapes {

            guard let country = countriesByISO2[shape.iso2] else { continue }

            let name = country.displayName
            guard !name.isEmpty else { continue }

            // The pole of inaccessibility of the country's largest part - the point
            // furthest from any edge of it.
            //
            // Natural Earth's own label_x/label_y was tried here and is worse: it is placed
            // for a printed world map, so Russia's sits over the Urals rather than in the
            // middle of Russia.
            let anchorNormalized = shape.labelAnchor

            let anchorWorld = CGPoint(
                x: worldRect.minX + anchorNormalized.x * worldRect.width,
                y: worldRect.minY + anchorNormalized.y * worldRect.height
            )
            let anchorScreen = worldToScreen(anchorWorld)

            // The unpadded box: how much room the outline really offers, not what the
            // camera would frame.
            let fitBox = shape.labelFitBoundingBoxNormalized

            let fitWorld = CGRect(
                x: worldRect.minX + fitBox.minX * worldRect.width,
                y: worldRect.minY + fitBox.minY * worldRect.height,
                width: fitBox.width * worldRect.width,
                height: fitBox.height * worldRect.height
            )
            let fitScreenRect = worldRectToScreenRect(fitWorld)

            guard fitScreenRect.intersects(viewportExpanded) else { continue }

            let fontSize = LabelLayout.fontSize
            let bboxArea = fitScreenRect.width * fitScreenRect.height

            // Relative to the viewport, not absolute: this is the gate that empties the
            // world view and fills in as the map is zoomed.
            let viewportArea = viewport.width * viewport.height
            guard viewportArea > 0,
                  bboxArea / viewportArea >= LabelLayout.minimumViewportCoverage
            else { continue }

            /// Whether a string fits the country's box at the drawing font size.
            ///
            /// Measured through UIKit and cached across frames. The SwiftUI Text is
            /// resolved further down, only for labels that actually get drawn.
            func fittingSize(of candidateText: String) -> CGSize? {

                let size = labelMetrics.size(for: candidateText, fontSize: fontSize)

                let minimumWidth = max(LabelLayout.minimumBoxWidthFloor,
                                       size.width + LabelLayout.textFitPaddingWidth)
                let minimumHeight = max(LabelLayout.minimumBoxHeightFloor,
                                        size.height + LabelLayout.textFitPaddingHeight)
                let minimumArea = max(LabelLayout.minimumBoxAreaFloor,
                                      size.width * size.height * LabelLayout.boxToTextAreaFactor)

                guard fitScreenRect.width >= minimumWidth,
                      fitScreenRect.height >= minimumHeight,
                      bboxArea >= minimumArea
                else { return nil }

                return size
            }

            // A name that does not fit is not drawn. Zooming in is what reveals it.
            //
            // Natural Earth's `abbrev` was tried here and reads as noise: a world view full
            // of "Fr.", "Ukr." and "S.Af." is worse than a world view with nothing on it.
            guard let textSize = fittingSize(of: name) else { continue }
            let drawnText = name

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
                name: drawnText,
                fontSize: fontSize,
                screenPoint: anchorScreen,
                textSize: textSize,
                rank: shape.labelInfo.rank,
                area: bboxArea,
                rect: labelRect
            ))
        }

        // Most important country first, so it keeps its label when two labels overlap.
        //
        // This used to be projected box area alone, which let the projection decide what
        // matters: in Web Mercator Niger outranks France. Natural Earth's own importance
        // ranking decides now, and area only breaks ties within one rank.
        candidates.sort {
            $0.rank != $1.rank ? $0.rank < $1.rank : $0.area > $1.area
        }

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
