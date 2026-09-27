//
//  StatusHatchingTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import CoreGraphics
import SwiftUI
import Testing
@testable import Countries

/// Covers the hatch geometry that carries the tracking status when colour cannot.
///
/// The point of the hatch is that visited and wishlisted are told apart *without* colour, so
/// the one property that must never break is that the two directions actually differ. A
/// screenshot cannot state that; these can.
struct StatusHatchingTests {

    // MARK: - Helpers

    /// One hatch line, as the renderer would stroke it.
    private struct Segment {
        let start: CGPoint
        let end: CGPoint
    }

    /// Reads the line segments back out of a built path.
    ///
    /// - Parameter path: A path built by ``StatusHatching/path(covering:direction:spacing:)``.
    /// - Returns: One entry per line, in the order they were added.
    private func segments(of path: Path) -> [Segment] {

        var starts: [CGPoint] = []
        var segments: [Segment] = []

        path.forEach { element in
            switch element {
            case .move(let point):
                starts.append(point)
            case .line(let point):
                if let start = starts.last {
                    segments.append(Segment(start: start, end: point))
                }
            default:
                break
            }
        }

        return segments
    }

    /// A square area to hatch, large enough for several lines at the shipped spacing.
    private static let area = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Direction

    @Test func test_path_rising_leansLeftGoingDown() {

        // Arrange / Act
        let path = StatusHatching.path(covering: Self.area,
                                       direction: .rising,
                                       spacing: StatusHatching.spacing)

        // Assert: y grows downwards on screen, so a line that ends further left rises.
        let lines = segments(of: path)
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.end.x < $0.start.x })
    }

    @Test func test_path_falling_leansRightGoingDown() {

        let path = StatusHatching.path(covering: Self.area,
                                       direction: .falling,
                                       spacing: StatusHatching.spacing)

        let lines = segments(of: path)
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.end.x > $0.start.x })
    }

    /// The property the whole ticket rests on: the two statuses cannot look the same.
    @Test func test_path_theTwoDirectionsAreOpposite() {

        let rising = segments(of: StatusHatching.path(covering: Self.area,
                                                      direction: .rising,
                                                      spacing: StatusHatching.spacing))
        let falling = segments(of: StatusHatching.path(covering: Self.area,
                                                       direction: .falling,
                                                       spacing: StatusHatching.spacing))

        let risingSlope = rising[0].end.x - rising[0].start.x
        let fallingSlope = falling[0].end.x - falling[0].start.x

        #expect(risingSlope * fallingSlope < 0)
        #expect(abs(risingSlope) == abs(fallingSlope))
    }

    // MARK: - Coverage

    @Test func test_path_coversTheAreaFromEdgeToEdge() {

        for direction in [StatusHatching.Direction.rising, .falling] {

            let lines = segments(of: StatusHatching.path(covering: Self.area,
                                                         direction: direction,
                                                         spacing: StatusHatching.spacing))

            // Every line spans the full height, and together they reach past both sides, so
            // no corner of the country is left unhatched.
            #expect(lines.allSatisfy { $0.start.y == Self.area.minY })
            #expect(lines.allSatisfy { $0.end.y == Self.area.maxY })

            let leftmost = lines.flatMap { [$0.start.x, $0.end.x] }.min() ?? .infinity
            let rightmost = lines.flatMap { [$0.start.x, $0.end.x] }.max() ?? -.infinity
            #expect(leftmost <= Self.area.minX)
            #expect(rightmost >= Self.area.maxX)
        }
    }

    @Test func test_path_spacingIsMeasuredPerpendicularToTheLines() {

        let spacing: CGFloat = 10
        let lines = segments(of: StatusHatching.path(covering: Self.area,
                                                     direction: .falling,
                                                     spacing: spacing))

        // The lines run at 45 degrees, so a horizontal step of `s` puts them `s / sqrt(2)`
        // apart. The step is scaled up by sqrt(2) to keep the perpendicular distance at
        // `spacing`; anything else makes the hatch denser than it was asked to be.
        let horizontalStep = lines[1].start.x - lines[0].start.x
        let perpendicular = horizontalStep / 2.squareRoot()

        #expect(abs(perpendicular - spacing) < 0.0001)
    }

    // MARK: - Bounds

    @Test func test_path_emptyArea_producesNothing() {

        let path = StatusHatching.path(covering: .zero,
                                       direction: .rising,
                                       spacing: StatusHatching.spacing)

        #expect(path.isEmpty)
    }

    @Test func test_path_absurdlySmallSpacing_isCappedRatherThanUnbounded() {

        // A degenerate camera must not be able to ask for millions of lines.
        let path = StatusHatching.path(covering: Self.area,
                                       direction: .rising,
                                       spacing: 0.00001)

        #expect(segments(of: path).count == StatusHatching.maximumLineCount)
    }

    @Test func test_path_nonPositiveSpacing_producesNothing() {

        let path = StatusHatching.path(covering: Self.area,
                                       direction: .rising,
                                       spacing: 0)

        #expect(path.isEmpty)
    }
}
