//
//  MapPerformanceBudget.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// The numbers "the map is fast enough" stands for.
///
/// Every value here was measured, not chosen. `MapPerformanceBudgetTests` rasterises one frame
/// of the real country geometry into a bitmap context and compares it against these ceilings, so
/// a change that makes the map more expensive fails a test instead of being noticed on a device
/// months later. `docs/map-performance-budget.md` records what was measured, on what, and how to
/// repeat it.
///
/// - Note: The ceilings are deliberately not the measured values. They are measured value times
///   two, because the figures come from a simulator sharing a Mac with whatever else is running
///   and a tight absolute ceiling would fail on a busy machine rather than on a regression. What
///   is tight is ``previewCostShare``, which is a ratio between two measurements taken seconds
///   apart and therefore survives a noisy machine.
nonisolated enum MapPerformanceBudget {

    // MARK: - Frame budget

    /// Highest acceptable cost of one full-detail frame, in milliseconds.
    ///
    /// Measured at 60-65 ms for the whole world at once, which is the worst case the interactive
    /// map never actually draws: on screen the camera is zoomed in and ``ScaledPathCache`` and
    /// clipping keep most of that geometry out of the pass.
    static let fullFrameMilliseconds: Double = 130

    /// Highest acceptable cost of one preview frame, in milliseconds.
    ///
    /// Measured at 11-13 ms. The dashboard draws this once and then leaves it alone, so the
    /// number that matters is the first appearance of the main screen, not a frame rate.
    static let previewFrameMilliseconds: Double = 26

    /// Highest acceptable cost of one overview frame, in milliseconds.
    ///
    /// The level the interactive map draws at the world view since [D-11]. Measured at 18 ms in
    /// the standalone CoreGraphics harness, so the ceiling follows the same doubling as the
    /// others. Remeasure in the simulator when D-11 merges — this figure has not been taken
    /// under the same conditions as the two above.
    static let overviewFrameMilliseconds: Double = 40

    /// Highest acceptable cost of a preview frame as a share of a full-detail frame.
    ///
    /// Measured at 0.18-0.20. This is the number that actually protects the dashboard: a preview that
    /// costs nearly as much as the interactive map has stopped being a preview, however fast the
    /// machine it was measured on happened to be.
    static let previewCostShare: Double = 0.30

    // MARK: - Lookup

    /// The frame budget for one level of detail.
    ///
    /// - Parameter variant: The level of detail being measured.
    /// - Returns: Milliseconds allowed for one frame.
    static func frameMilliseconds(for variant: FlatMapShapeCache.Variant) -> Double {

        switch variant {
        case .full: return fullFrameMilliseconds
        case .overview: return overviewFrameMilliseconds
        case .light: return previewFrameMilliseconds
        }
    }
}
