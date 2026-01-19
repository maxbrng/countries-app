//
//  FlatMapRenderer.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import SwiftData
import CoreGraphics

struct FlatMapRenderer: View, Animatable {

    let shapes: [RenderCountryShape]
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
        selectionEnabled: Bool
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
    }

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

            for shape in shapes {
                let path = scaledPath(shape.path, into: worldRect)
                let isSelected = (selectionEnabled && selectedISO2 == shape.iso2)

                let fillColor = fill(for: shape.iso2, isSelected: isSelected)
                let strokeColor = isSelected ? Color(uiColor: .label) : Color(uiColor: .systemBackground).opacity(0.75)
                let lineWidth = (isSelected ? 1.2 : 0.4) / (interactiveEnabled ? currentScale : 1)

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

    private func fill(for iso2: String, isSelected: Bool) -> Color {
        
        if let country = countriesByISO2[iso2] {
            
            switch country.status {
            case .visited:
                return Color(uiColor: .label).opacity(0.55)
            case .wishlist:
                return .orange.opacity(0.75)
            default:
                return Color(uiColor: .label).opacity(0.22)
            }
        }
        return Color(uiColor: .systemFill)
    }

    // MARK: - Labels (collision-free)

    private func drawLabels(in context: GraphicsContext,
                            cameraCenter: CGPoint,
                            currentScale: CGFloat,
                            offsetX: CGFloat,
                            offsetY: CGFloat) {
        
        struct Candidate {
            let iso2: String
            let screenPoint: CGPoint
            let resolved: GraphicsContext.ResolvedText
            let textSize: CGSize
            let score: CGFloat
            let rect: CGRect
        }

        func worldToScreen(_ p: CGPoint) -> CGPoint {
            
            let transformedX = (p.x - cameraCenter.x) * currentScale + cameraCenter.x + offsetX
            let transformedY = (p.y - cameraCenter.y) * currentScale + cameraCenter.y + offsetY
            
            return interactiveEnabled ? CGPoint(x: transformedX, y: transformedY) : p
        }

        func worldRectToScreenRect(_ r: CGRect) -> CGRect {
            
            let p1 = worldToScreen(CGPoint(x: r.minX, y: r.minY))
            let p2 = worldToScreen(CGPoint(x: r.maxX, y: r.minY))
            let p3 = worldToScreen(CGPoint(x: r.minX, y: r.maxY))
            let p4 = worldToScreen(CGPoint(x: r.maxX, y: r.maxY))

            let minX = min(p1.x, p2.x, p3.x, p4.x)
            let maxX = max(p1.x, p2.x, p3.x, p4.x)
            let minY = min(p1.y, p2.y, p3.y, p4.y)
            let maxY = max(p1.y, p2.y, p3.y, p4.y)

            return CGRect(x: minX, y: minY, width: max(0.1, maxX - minX), height: max(0.1, maxY - minY))
        }

        let viewportExpanded = viewport.insetBy(dx: -80, dy: -80)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(256)

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

            let baseFontSize: CGFloat = 10
            let fontScale = min(1.0, 1.0 / max(currentScale, 0.0001))
            let fontSize = (baseFontSize * fontScale).clamped(8, 14)

            let text = Text(name)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label).opacity(0.70))

            let resolved = context.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))

            let paddingWidth: CGFloat = 10
            let paddingHeight: CGFloat = 8

            let minimumBoxWidth: CGFloat = max(26, textSize.width + paddingWidth)
            let minimumBoxHeight: CGFloat = max(16, textSize.height + paddingHeight)
            let minimumArea: CGFloat = max(200, (textSize.width * textSize.height) * 2.4)

            let bboxArea = focusScreenRect.width * focusScreenRect.height
            
            guard focusScreenRect.width >= minimumBoxWidth,
                  focusScreenRect.height >= minimumBoxHeight,
                  bboxArea >= minimumArea
            else { continue }

            let collisionPadding: CGFloat = 6
            let labelRect = CGRect(
                x: anchorScreen.x - textSize.width * 0.5 - collisionPadding,
                y: anchorScreen.y - textSize.height * 0.5 - collisionPadding,
                width: textSize.width + collisionPadding * 2,
                height: textSize.height + collisionPadding * 2
            )
            guard labelRect.intersects(viewportExpanded) else { continue }

            candidates.append(.init(
                iso2: shape.iso2,
                screenPoint: anchorScreen,
                resolved: resolved,
                textSize: textSize,
                score: bboxArea,
                rect: labelRect
            ))
        }

        candidates.sort { $0.score > $1.score }

        struct CellKey: Hashable { let x: Int; let y: Int }
        let cellSize: CGFloat = 120
        var grid: [CellKey: [CGRect]] = [:]
        grid.reserveCapacity(256)

        func cellRange(for rect: CGRect) -> (Int, Int, Int, Int) {
            let x0 = Int(floor(rect.minX / cellSize))
            let x1 = Int(floor(rect.maxX / cellSize))
            let y0 = Int(floor(rect.minY / cellSize))
            let y1 = Int(floor(rect.maxY / cellSize))
            return (x0, x1, y0, y1)
        }

        func intersectsPlaced(_ rect: CGRect) -> Bool {
            let (x0, x1, y0, y1) = cellRange(for: rect)
            for yy in y0...y1 {
                for xx in x0...x1 {
                    let key = CellKey(x: xx, y: yy)
                    if let rects = grid[key] {
                        for r in rects where r.intersects(rect) {
                            return true
                        }
                    }
                }
            }
            return false
        }

        func insertPlaced(_ rect: CGRect) {
            
            let (x0, x1, y0, y1) = cellRange(for: rect)
            
            for yy in y0...y1 {
                
                for xx in x0...x1 {
                    let key = CellKey(x: xx, y: yy)
                    grid[key, default: []].append(rect)
                }
            }
        }

        for candidate in candidates {
            
            if intersectsPlaced(candidate.rect) { continue }
            
            insertPlaced(candidate.rect)
            
            context.draw(candidate.resolved,
                         at: candidate.screenPoint,
                         anchor: .center)
        }
    }

    // MARK: - Path scaling

    private func scaledPath(_ cgPath: CGPath, into rect: CGRect) -> Path {
        
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)
        
        return Path(cgPath.copy(using: &transform) ?? cgPath)
    }
}
