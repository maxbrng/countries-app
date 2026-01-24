//
//  FlatPathBuilder.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

nonisolated enum FlatPathBuilder {

    // MARK: - Variant

    enum Variant: Sendable {
        /// Interactive / detail mode (uses hybrid centroid + polylabel).
        case full
        /// Preview / lightweight mode (no polylabel).
        case light
    }
    
    // CGPath is not formally Sendable. We only pass results within the same task.
    // Marking it unchecked keeps Swift 6 concurrency checking happy.
    struct BuildResult: @unchecked Sendable {
        let path: CGPath
        let labelAnchor: CGPoint
        let focusBoundingBox: CGRect
    }
    
    // MARK: - Internals
    
    struct Candidate {
        let area: Double
        let centroid: CGPoint
        let boundingBox: CGRect
        let ring: [CGPoint]
        let compactness: Double // area / bboxArea
    }
    nonisolated static func build(
        from geometry: GeoJSON.Geometry,
        projectionMode: FlatMapProjectionMode,
        iso2: String,
        variant: Variant = .full
    ) -> BuildResult {
        
        let mutablePath = CGMutablePath()
        var candidates: [Candidate] = []
        
        func addRingToPath(_ ring: [[Double]]) {
            
            guard ring.count >= 2 else { return }
            
            let first = ring[0]
            let start = FlatMapProjection.projectLongitudeLatitude(longitude: first[0],
                                                                   latitude: first[1],
                                                                   mode: projectionMode)
            mutablePath.move(to: start)
            
            for coordinate in ring.dropFirst() {
                let point = FlatMapProjection.projectLongitudeLatitude(longitude: coordinate[0],
                                                                       latitude: coordinate[1],
                                                                       mode: projectionMode)
                mutablePath.addLine(to: point)
            }
            mutablePath.closeSubpath()
        }
        
        func considerOuterRing(_ ring: [[Double]]) {
            
            let points = ring.map { FlatMapProjection.projectLongitudeLatitude(longitude: $0[0],
                                                                               latitude: $0[1],
                                                                               mode: projectionMode) }
            let (signedArea, centroid) = polygonAreaAndCentroid(points)
            let area = abs(signedArea)
            guard area > 0, centroid.x.isFinite, centroid.y.isFinite else { return }
            
            let boundingBox = boundingBox(for: points)
            guard boundingBox.width > 0, boundingBox.height > 0 else { return }
            
            let bboxArea = Double(boundingBox.width * boundingBox.height)
            let compactness = bboxArea > 0 ? (area / bboxArea) : 0
            
            candidates.append(.init(area: area,
                                    centroid: centroid,
                                    boundingBox: boundingBox,
                                    ring: points,
                                    compactness: compactness))
        }
        
        switch geometry {
        case .polygon(let rings):
            for (ringIndex, ring) in rings.enumerated() {
                addRingToPath(ring)
                if ringIndex == 0 { considerOuterRing(ring) }
            }
            
        case .multiPolygon(let polygons):
            for polygon in polygons {
                for (ringIndex, ring) in polygon.enumerated() {
                    addRingToPath(ring)
                    if ringIndex == 0 { considerOuterRing(ring) }
                }
            }
        }
        
        let best = candidates.max(by: { $0.area < $1.area })
        
        let labelAnchor: CGPoint = {
            switch variant {
            case .full:
                return makeHybridLabelAnchor(bestCandidate: best)
            case .light:
                return makeLightLabelAnchor(bestCandidate: best)
            }
        }()
        let focusBoundingBox = chooseFocusBoundingBox(candidates: candidates, iso2: iso2)
        
        return .init(path: mutablePath,
                     labelAnchor: labelAnchor,
                     focusBoundingBox: focusBoundingBox)
    }
    
    // MARK: - Label anchor

    /// Lightweight label anchor: prefers centroid if inside, otherwise bbox center, otherwise cheap fallback.
    private static func makeLightLabelAnchor(bestCandidate: Candidate?) -> CGPoint {
        guard let bestCandidate else { return CGPoint(x: 0.5, y: 0.5) }

        let centroid = bestCandidate.centroid
        if pointInPolygon(centroid, bestCandidate.ring) { return centroid }

        let bboxCenter = CGPoint(x: bestCandidate.boundingBox.midX, y: bestCandidate.boundingBox.midY)
        if pointInPolygon(bboxCenter, bestCandidate.ring) { return bboxCenter }

        return pointOnSurfaceFallback(ring: bestCandidate.ring, bbox: bestCandidate.boundingBox) ?? centroid
    }
    
    private static func makeHybridLabelAnchor(bestCandidate: Candidate?) -> CGPoint {
        
        guard let bestCandidate else { return CGPoint(x: 0.5, y: 0.5) }
        
        let centroid = bestCandidate.centroid
        let centroidInside = pointInPolygon(centroid, bestCandidate.ring)
        
        let boundingWidth = max(bestCandidate.boundingBox.width, 0.000001)
        let boundingHeight = max(bestCandidate.boundingBox.height, 0.000001)
        let aspect = boundingWidth / boundingHeight
        let skinnyFactor = max(aspect, 1 / aspect) // >= 1
        
        let isCompact = (skinnyFactor < 1.6) && (bestCandidate.compactness > 0.22)
        if isCompact, centroidInside {
            return centroid
        }
        
        let polylabelPoint = stretchedPolylabel(bestCandidate.ring,
                                                bbox: bestCandidate.boundingBox,
                                                precision: 0.002) ?? polylabel(bestCandidate.ring, precision: 0.002)
        
        guard let polylabelPoint else {
            if centroidInside {
                return centroid
            }
            return pointOnSurfaceFallback(ring: bestCandidate.ring, bbox: bestCandidate.boundingBox) ?? centroid
        }
        
        // Blend centroid -> polylabel for skinny / non-compact shapes
        let skinnyT = CGFloat((skinnyFactor - 1.2) / 2.0).clamped(0, 1)
        let compactT = CGFloat((0.25 - bestCandidate.compactness) / 0.25).clamped(0, 1)
        let t = max(skinnyT, compactT)
        
        let mixed = interpolate(from: centroid, to: polylabelPoint, t: t)
        
        if pointInPolygon(mixed, bestCandidate.ring) {
            return mixed
        }
        if pointInPolygon(polylabelPoint, bestCandidate.ring) {
            return polylabelPoint
        }
        if centroidInside {
            return centroid
        }
        
        return pointOnSurfaceFallback(ring: bestCandidate.ring, bbox: bestCandidate.boundingBox) ?? centroid
    }
    
    // MARK: - Focus bounding box
    
    private static func chooseFocusBoundingBox(candidates: [Candidate], iso2: String) -> CGRect {
        
        guard !candidates.isEmpty else {
            return CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        }
        
        let maxArea = candidates.map(\.area).max() ?? 0
        let areaThreshold = maxArea * 0.08
        
        var filteredCandidates = candidates.filter { $0.area >= areaThreshold }
        
        // USA: prefer lower 48 (keeps Alaska/Hawaii from dominating focus)
        if iso2 == "us" {
            let lower48 = filteredCandidates.filter { $0.centroid.y > 0.22 }
            if !lower48.isEmpty { filteredCandidates = lower48 }
        }
        
        let chosen = filteredCandidates.max(by: { $0.area < $1.area }) ?? candidates.max(by: { $0.area < $1.area })!
        
        return chosen.boundingBox.insetBy(dx: -0.01, dy: -0.01).clampedToUnit()
    }
    
    // MARK: - Geometry helpers
    
    private static func boundingBox(for points: [CGPoint]) -> CGRect {
        
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        
        guard minX.isFinite,
              minY.isFinite,
              maxX.isFinite,
              maxY.isFinite
        else { return .zero }
        
        return CGRect(x: minX,
                      y: minY,
                      width: max(0.0001, maxX - minX),
                      height: max(0.0001, maxY - minY))
    }
    
    private static func polygonAreaAndCentroid(_ points: [CGPoint]) -> (Double, CGPoint) {
        
        guard points.count >= 3 else { return (0, CGPoint(x: 0.5, y: 0.5)) }
        
        var area: Double = 0
        var centroidX: Double = 0
        var centroidY: Double = 0
        
        for index in 0..<points.count {
            let p = points[index]
            let q = points[(index + 1) % points.count]
            let cross = Double(p.x * q.y - q.x * p.y)
            area += cross
            centroidX += (Double(p.x) + Double(q.x)) * cross
            centroidY += (Double(p.y) + Double(q.y)) * cross
        }
        
        area *= 0.5
        let denominator = 6.0 * area
        if denominator == 0 { return (0, CGPoint(x: 0.5, y: 0.5)) }
        
        return (area, CGPoint(x: centroidX / denominator,
                              y: centroidY / denominator))
    }
    
    // MARK: - Polylabel (same algorithm, isolated)
    
    private struct Cell {
        let center: CGPoint
        let half: CGFloat
        let distance: CGFloat
        let maxDistance: CGFloat
    }
    
    private static func polylabel(_ ring: [CGPoint], precision: CGFloat) -> CGPoint? {
        
        guard ring.count >= 3 else { return nil }
        
        let bbox = boundingBox(for: ring)
        
        guard bbox.width > 0, bbox.height > 0 else { return nil }
        
        let minX = bbox.minX
        let minY = bbox.minY
        let width = bbox.width
        let height = bbox.height
        
        let cellSize = max(width, height)
        guard cellSize > 0 else { return nil }
        let half = cellSize / 2
        
        var cells: [Cell] = []
        var y = minY
        while y < minY + height {
            var x = minX
            while x < minX + width {
                let c = CGPoint(x: x + half, y: y + half)
                let d = signedDistance(c, ring)
                cells.append(makeCell(center: c, half: half, distance: d))
                x += cellSize
            }
            y += cellSize
        }
        
        var best = makeCell(center: CGPoint(x: bbox.midX, y: bbox.midY),
                            half: 0,
                            distance: signedDistance(CGPoint(x: bbox.midX, y: bbox.midY), ring))
        
        if let candidateBest = cells.max(by: { $0.distance < $1.distance }), candidateBest.distance > best.distance {
            best = candidateBest
        }
        
        while true {
            cells.sort { $0.maxDistance > $1.maxDistance }
            guard let cell = cells.first else { break }
            cells.removeFirst()
            
            if cell.distance > best.distance { best = cell }
            if (cell.maxDistance - best.distance) <= precision { break }
            
            let half2 = cell.half / 2
            guard half2 > 0 else { continue }
            
            let c = cell.center
            let offsets = [
                CGPoint(x: -half2, y: -half2), CGPoint(x:  half2, y: -half2),
                CGPoint(x: -half2, y:  half2), CGPoint(x:  half2, y:  half2)
            ]
            
            for offset in offsets {
                let newCenter = CGPoint(x: c.x + offset.x, y: c.y + offset.y)
                let d = signedDistance(newCenter, ring)
                cells.append(makeCell(center: newCenter,
                                      half: half2,
                                      distance: d))
            }
        }
        
        return best.distance > 0 ? best.center : nil
    }
    
    private static func stretchedPolylabel(_ ring: [CGPoint], bbox: CGRect, precision: CGFloat) -> CGPoint? {
        
        if let p = polylabel(ring, precision: precision) { return p }
        
        let centerX = bbox.midX
        let centerY = bbox.midY
        
        let sampleCount = 11
        var bestPoint: CGPoint?
        var bestDistance: CGFloat = -CGFloat.greatestFiniteMagnitude
        
        for i in 0..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount - 1)
            let px = bbox.minX + (bbox.width * t)
            let py = bbox.minY + (bbox.height * t)
            
            let candidates = [CGPoint(x: px, y: centerY), CGPoint(x: centerX, y: py)]
            for candidate in candidates {
                let distance = signedDistance(candidate, ring)
                if distance > bestDistance {
                    bestDistance = distance
                    bestPoint = candidate
                }
            }
        }
        
        if let bestPoint, bestDistance > 0 { return bestPoint }
        return nil
    }
    
    private static func makeCell(center: CGPoint,
                                 half: CGFloat,
                                 distance: CGFloat) -> Cell {
        
        let maxDist = distance + half * CGFloat(2).squareRoot()
        return Cell(center: center,
                    half: half,
                    distance: distance,
                    maxDistance: maxDist)
    }
    
    private static func signedDistance(_ point: CGPoint, _ ring: [CGPoint]) -> CGFloat {
        
        let inside = pointInPolygon(point, ring)
        let distance = distanceToPolygonEdges(point, ring)
        
        return inside ? distance : -distance
    }
    
    private static func pointInPolygon(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        
        var inside = false
        var j = ring.count - 1
        
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[j]
            let intersects =
            ((a.y > point.y) != (b.y > point.y)) &&
            (point.x < (b.x - a.x) * (point.y - a.y) / ((b.y - a.y) + 0.0000001) + a.x)
            
            if intersects { inside.toggle() }
            j = i
        }
        
        return inside
    }
    
    private static func distanceToPolygonEdges(_ point: CGPoint, _ ring: [CGPoint]) -> CGFloat {
        
        var minDistance = CGFloat.greatestFiniteMagnitude
        
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            minDistance = min(minDistance, distancePointToSegment(point, a, b))
        }
        
        return minDistance.isFinite ? minDistance : 0
    }
    
    private static func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let ab2 = ab.x * ab.x + ab.y * ab.y
        
        if ab2 <= 0 { return hypot(ap.x, ap.y) }
        
        var t = (ap.x * ab.x + ap.y * ab.y) / ab2
        t = max(0, min(1, t))
        let projection = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        
        return hypot(p.x - projection.x, p.y - projection.y)
    }
    
    private static func pointOnSurfaceFallback(ring: [CGPoint], bbox: CGRect) -> CGPoint? {
        
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        
        if pointInPolygon(center, ring) { return center }
        
        let steps = 36
        let radiusStep = min(bbox.width, bbox.height) / CGFloat(steps)
        
        for step in 1...steps {
            let radius = CGFloat(step) * radiusStep
            let angles = 12
            
            for a in 0..<angles {
                let angle = (CGFloat(a) / CGFloat(angles)) * 2 * .pi
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                
                if pointInPolygon(p, ring) { return p }
            }
        }
        return nil
    }
    
    private static func interpolate(from a: CGPoint,
                                    to b: CGPoint,
                                    t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t,
                y: a.y + (b.y - a.y) * t)
    }
}
