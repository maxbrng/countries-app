//
//  PolylineSimplifierTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import Testing
@testable import Countries

/// Covers the simplification and area helpers the map pipeline builds every shape with.
struct PolylineSimplifierTests {

    // MARK: - Simplify

    @Test func test_simplify_collinearPoints_keepsOnlyTheEndpoints() {

        let line = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 0),
                    CGPoint(x: 2, y: 0),
                    CGPoint(x: 3, y: 0)]

        let simplified = PolylineSimplifier.simplify(line, tolerance: 0.01)

        #expect(simplified == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)])
    }

    @Test func test_simplify_peakTallerThanTheTolerance_isKept() {

        let line = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 0),
                    CGPoint(x: 2, y: 1),
                    CGPoint(x: 3, y: 0),
                    CGPoint(x: 4, y: 0)]

        let simplified = PolylineSimplifier.simplify(line, tolerance: 0.1)

        #expect(simplified.contains(CGPoint(x: 2, y: 1)))
    }

    @Test func test_simplify_peakShorterThanTheTolerance_isDropped() {

        let line = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 0.01),
                    CGPoint(x: 2, y: 0.02),
                    CGPoint(x: 3, y: 0.01),
                    CGPoint(x: 4, y: 0)]

        let simplified = PolylineSimplifier.simplify(line, tolerance: 0.5)

        #expect(simplified == [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)])
    }

    @Test func test_simplify_threeOrFewerPoints_areReturnedUnchanged() {

        // Deliberate: below this length there is nothing worth the pass, so even an
        // interior point well inside the tolerance survives.
        let line = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 0.01),
                    CGPoint(x: 2, y: 0)]

        #expect(PolylineSimplifier.simplify(line, tolerance: 100) == line)
    }

    @Test func test_simplify_alwaysKeepsFirstAndLastPoint() {

        let ring = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 0.001),
                    CGPoint(x: 2, y: 0.001),
                    CGPoint(x: 3, y: 0.002),
                    CGPoint(x: 0, y: 0)]

        let simplified = PolylineSimplifier.simplify(ring, tolerance: 10)

        #expect(simplified.first == ring.first)
        #expect(simplified.last == ring.last)
    }

    @Test func test_simplify_zeroTolerance_returnsTheInputUnchanged() {

        let line = [CGPoint(x: 0, y: 0),
                    CGPoint(x: 1, y: 1),
                    CGPoint(x: 2, y: 0),
                    CGPoint(x: 3, y: 4)]

        #expect(PolylineSimplifier.simplify(line, tolerance: 0) == line)
        #expect(PolylineSimplifier.simplify(line, tolerance: -1) == line)
    }

    @Test func test_simplify_neverReturnsMorePointsThanItWasGiven() {

        let ring = (0..<50).map { index in
            CGPoint(x: CGFloat(index), y: CGFloat(index % 3))
        }

        for tolerance in [CGFloat(0.1), 0.5, 1, 5] {
            #expect(PolylineSimplifier.simplify(ring, tolerance: tolerance).count <= ring.count)
        }
    }

    // MARK: - Ring area

    @Test func test_ringArea_unitSquare_isOne() {

        let square = [CGPoint(x: 0, y: 0),
                      CGPoint(x: 1, y: 0),
                      CGPoint(x: 1, y: 1),
                      CGPoint(x: 0, y: 1)]

        #expect(abs(PolylineSimplifier.ringArea(square) - 1) < 1e-12)
    }

    @Test func test_ringArea_windingOrderDoesNotChangeIt() {

        let square = [CGPoint(x: 0, y: 0),
                      CGPoint(x: 1, y: 0),
                      CGPoint(x: 1, y: 1),
                      CGPoint(x: 0, y: 1)]

        #expect(PolylineSimplifier.ringArea(square) == PolylineSimplifier.ringArea(square.reversed()))
    }

    @Test func test_ringArea_fewerThanThreeVertices_isZero() {

        #expect(PolylineSimplifier.ringArea([]) == 0)
        #expect(PolylineSimplifier.ringArea([CGPoint(x: 1, y: 1)]) == 0)
        #expect(PolylineSimplifier.ringArea([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]) == 0)
    }
}
