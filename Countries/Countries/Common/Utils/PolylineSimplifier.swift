//
//  PolylineSimplifier.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import CoreGraphics

/// Ramer-Douglas-Peucker line simplification for the bundled world geometry.
///
/// The algorithm keeps the first and last point of a polyline and, for the segment
/// between them, the point that lies farthest from the straight connection. That point
/// is kept only when its distance exceeds the tolerance; the two resulting halves are
/// then simplified the same way. Points that never win such a split are dropped, so the
/// output is always a subset of the input and keeps its original order.
///
/// The bundled world geometry carries ~100k coordinates, far more detail than
/// either the globe or the small preview map can show. Simplifying before the
/// points ever reach MapKit or CoreGraphics is what keeps both cheap.
nonisolated enum PolylineSimplifier {

    // MARK: - Constants

    /// A polyline of three or fewer points has no interior point worth dropping.
    private static let simplifiablePointCountThreshold = 3

    /// A ring needs three vertices before it encloses any area.
    private static let minimumRingVertexCount = 3

    // MARK: - Simplification

    /// Simplifies a polyline, keeping its first and last point.
    ///
    /// - Parameters:
    ///   - points: The polyline in drawing order; for a ring, first and last point
    ///     coincide and both are kept.
    ///   - tolerance: The maximum distance a dropped point may have from the line that
    ///     replaces it, in the same unit as the points. Larger values remove more points
    ///     and flatten the outline further; values of `0` or less return the input
    ///     unchanged.
    /// - Returns: The kept points, in input order. Never more points than were passed in.
    /// - Note: Distances are compared squared, so no square root is taken per point.
    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {

        guard points.count > simplifiablePointCountThreshold,
              tolerance > 0
        else {
            return points
        }

        let toleranceSquared = tolerance * tolerance

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        // Explicit stack: recursion could go points.count deep on pathological rings.
        var segments: [(Int, Int)] = [(0, points.count - 1)]

        while let (first, last) = segments.popLast() {

            guard last > first + 1 else { continue }

            let start = points[first]
            let end = points[last]

            var maxDistanceSquared: CGFloat = 0
            var farthest = first

            for index in (first + 1)..<last {
                let distance = perpendicularDistanceSquared(points[index], start, end)
                if distance > maxDistanceSquared {
                    maxDistanceSquared = distance
                    farthest = index
                }
            }

            guard maxDistanceSquared > toleranceSquared else { continue }

            keep[farthest] = true
            segments.append((first, farthest))
            segments.append((farthest, last))
        }

        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for (index, point) in points.enumerated() where keep[index] {
            result.append(point)
        }

        return result
    }

    // MARK: - Geometry

    /// Squared distance from a point to the infinite line through `start` and `end`.
    ///
    /// - Parameters:
    ///   - point: The point to measure.
    ///   - start: First point of the line.
    ///   - end: Second point of the line.
    /// - Returns: The squared distance, or the squared distance to `start` when `start`
    ///   and `end` are the same point and therefore define no line.
    private static func perpendicularDistanceSquared(_ point: CGPoint,
                                                     _ start: CGPoint,
                                                     _ end: CGPoint) -> CGFloat {

        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            let px = point.x - start.x
            let py = point.y - start.y
            return px * px + py * py
        }

        // Cross product of the segment and the vector to the point: its magnitude is the
        // area of the spanned parallelogram, so dividing by the segment length gives the
        // distance. Both sides are kept squared.
        let cross = dx * (start.y - point.y) - dy * (start.x - point.x)
        return (cross * cross) / lengthSquared
    }

    // MARK: - Area

    /// Approximate area of a closed ring, via the shoelace formula.
    ///
    /// The result is half the absolute cross-product sum over all edges, in squared point
    /// units. Callers use it to drop specks that would not cover a pixel anyway.
    ///
    /// - Parameter points: The ring vertices in order; the closing edge back to the first
    ///   vertex is added implicitly.
    /// - Returns: The unsigned area, or `0` for fewer than three vertices.
    /// - Note: Unsigned, so the winding order of the ring does not matter.
    static func ringArea(_ points: [CGPoint]) -> CGFloat {

        guard points.count >= minimumRingVertexCount else { return 0 }

        var sum: CGFloat = 0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }

        return abs(sum) * 0.5
    }
}
