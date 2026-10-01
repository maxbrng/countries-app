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
    /// Lowercased ISO2 code of the country the user lives in, or `nil` when none is set.
    ///
    /// Marked on the interactive map only. On the dashboard preview the whole world is a few
    /// centimetres wide and a marker would be a dot on a dot.
    let homeISO2: String?

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

    /// The marker drawn over the country the user lives in.
    ///
    /// Modelled on the dot a map puts where you are: a filled disc inside a ring of the map's
    /// own background, so it reads against any fill underneath it. Drawn in screen points, so
    /// it keeps its size at every zoom rather than growing into a blob.
    private enum HomeMarker {

        /// Radius of the filled disc, in screen points.
        static let radius: CGFloat = 5

        /// Width of the ring drawn around the disc.
        static let ringWidth: CGFloat = 2

        /// Radius of the soft halo under the disc, as a multiple of ``radius``.
        static let haloRadiusFactor: CGFloat = 2.6

        /// Opacity of that halo.
        static let haloOpacity: Double = 0.25
    }

    /// Thresholds and paddings of the label placement pass. All values are tuned
    /// against the real country set; changing one changes how many labels survive.
    private enum LabelLayout {

        /// Labels stay alive slightly outside the viewport so they do not pop in at
        /// the edge while panning.
        static let viewportOverscan: CGFloat = 80

        /// Slack added around the text before it is asked to fit inside the country.
        ///
        /// Keeps a name off its own border instead of letting it touch the coastline.
        static let clearancePadding: CGFloat = 3

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
    ///   - homeISO2: Lowercased ISO2 code of the home country, or `nil`.
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
        homeISO2: String?,
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
        self.homeISO2 = homeISO2
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

            drawHomeMarker(in: context,
                           cameraCenter: cameraCenter,
                           currentScale: currentScale,
                           offsetX: offsetX,
                           offsetY: offsetY)

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
    /// How much a country deserves its label when two of them overlap.
    ///
    /// Natural Earth's own importance decides, and the projected box area only breaks ties
    /// within one rank. Area alone let the projection decide what matters: in Web Mercator
    /// Niger outranks France.
    ///
    /// - Parameters:
    ///   - shape: The country being considered.
    ///   - boxArea: Its projected bounding box area, in square points.
    ///   - isSelected: Whether this is the country the user has tapped.
    /// - Returns: A score, higher wins. The selection always wins.
    private func labelScore(for shape: RenderCountryShape,
                            boxArea: CGFloat,
                            isSelected: Bool) -> CGFloat {

        guard !isSelected else { return .greatestFiniteMagnitude }

        // Rank is 1...10 with 1 the most important, so it is inverted and weighted far above
        // any area a box can reach on screen.
        let rankWeight = CGFloat(LabelInfo.maximumRank - shape.labelInfo.rank)

        return rankWeight * Self.labelRankScoreWeight + boxArea
    }

    /// How much one step of ``LabelInfo/rank`` is worth against the box area.
    ///
    /// Large enough that a more important country always outranks a larger one, leaving area
    /// as the tie-breaker inside a rank rather than as the decision.
    private static let labelRankScoreWeight: CGFloat = 1_000_000

    /// Draws the marker over the country the user lives in.
    ///
    /// Nothing is drawn on a preview, and nothing when no home country is set. The marker sits
    /// at the country's label anchor — the point furthest from any of its edges — so it lands
    /// in the middle of the landmass rather than at the centre of its bounding box, which for
    /// a country like Norway is in the sea.
    ///
    /// - Parameters:
    ///   - context: The unscaled canvas context. The marker is placed in screen space by hand
    ///     so that it keeps its size at every zoom instead of growing with the camera.
    ///   - cameraCenter: Center of the viewport, the fixed point of the camera transform.
    ///   - currentScale: `fitScale` times `userZoom`.
    ///   - offsetX: Horizontal camera offset in points.
    ///   - offsetY: Vertical camera offset in points.
    private func drawHomeMarker(in context: GraphicsContext,
                                cameraCenter: CGPoint,
                                currentScale: CGFloat,
                                offsetX: CGFloat,
                                offsetY: CGFloat) {

        guard interactiveEnabled,
              let homeISO2,
              let shape = shapes.first(where: { $0.iso2 == homeISO2 })
        else { return }

        let anchorWorld = CGPoint(
            x: worldRect.minX + shape.labelAnchor.x * worldRect.width,
            y: worldRect.minY + shape.labelAnchor.y * worldRect.height
        )

        let point = CGPoint(
            x: (anchorWorld.x - cameraCenter.x) * currentScale + cameraCenter.x + offsetX,
            y: (anchorWorld.y - cameraCenter.y) * currentScale + cameraCenter.y + offsetY
        )

        guard viewport.insetBy(dx: -HomeMarker.radius * HomeMarker.haloRadiusFactor,
                               dy: -HomeMarker.radius * HomeMarker.haloRadiusFactor)
                .contains(point)
        else { return }

        /// A circle of `radius` centred on the marker's point.
        func disc(radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: point.x - radius,
                                   y: point.y - radius,
                                   width: radius * 2,
                                   height: radius * 2))
        }

        let haloRadius = HomeMarker.radius * HomeMarker.haloRadiusFactor

        context.fill(disc(radius: haloRadius),
                     with: .color(MapPalette.homeMarker.opacity(HomeMarker.haloOpacity)))

        // The ring is the map's own background, so the dot separates from the fill under it
        // whatever that fill happens to be.
        context.stroke(disc(radius: HomeMarker.radius + HomeMarker.ringWidth / 2),
                       with: .color(MapPalette.ocean),
                       lineWidth: HomeMarker.ringWidth)

        context.fill(disc(radius: HomeMarker.radius), with: .color(MapPalette.homeMarker))
    }

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

        guard viewport.height > 0 else { return }

        // Nothing at all while the map is at or near its minimum zoom - except the country the
        // user has just tapped, which is checked per shape below. A selection that says nothing
        // about which country was selected is not a selection.
        let worldHeightOnScreen = worldRect.height * currentScale
        let zoomAllowsLabels =
            worldHeightOnScreen / viewport.height >= LabelLayout.minimumWorldToViewportScale

        let hasSelection = selectionEnabled && selectedISO2 != nil
        guard zoomAllowsLabels || hasSelection else { return }

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

            let isSelected = (selectionEnabled && selectedISO2 == shape.iso2)
            guard zoomAllowsLabels || isSelected else { continue }

            let fontSize = LabelLayout.fontSize
            let bboxArea = focusScreenRect.width * focusScreenRect.height
            let textSize = labelMetrics.size(for: name, fontSize: fontSize)

            // Does the name fit *inside the country*, rather than inside the box around it?
            //
            // `labelClearanceNormalized` is the radius of the largest circle that fits in the
            // outline at the anchor, so this asks whether the text rectangle fits in that
            // circle. The box could not answer it: Croatia's box is wide while the land under
            // it is a narrow crescent, which is how its name ended up outside the country.
            //
            // The smaller of the two world dimensions converts the radius, because the
            // normalized space is not square and a label that fits has to fit on both axes.
            let clearanceOnScreen = shape.labelClearanceNormalized
                * min(worldRect.width, worldRect.height)
                * currentScale

            let halfDiagonal = (textSize.width * textSize.width
                                + textSize.height * textSize.height).squareRoot() / 2

            // The selected country is exempt. Tapping a country and not being told which one
            // it is makes the selection useless, so its name is drawn wherever the anchor is.
            guard isSelected || halfDiagonal + LabelLayout.clearancePadding <= clearanceOnScreen
            else { continue }

            // Natural Earth's `abbrev` was tried instead of hiding a name that does not fit,
            // and it reads as noise: a map full of "Fr.", "Ukr." and "S.Af." is worse than a
            // map with fewer names on it.
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
                name: name,
                fontSize: fontSize,
                screenPoint: anchorScreen,
                textSize: textSize,
                score: labelScore(for: shape, boxArea: bboxArea, isSelected: isSelected),
                rect: labelRect
            ))
        }

        // Largest country first, so it keeps its label when two labels overlap.
        // Highest score first, so it keeps its label when two labels overlap.
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
