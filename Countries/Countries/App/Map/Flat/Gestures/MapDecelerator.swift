//
//  MapDecelerator.swift
//  Countries
//
//  Created by Max Breuning on 05.08.26.
//

import QuartzCore
import CoreGraphics

/// Inertial scrolling driven by the display refresh instead of a fixed timer.
///
/// The previous implementation stepped a `Task.sleep(16ms)` loop and multiplied the
/// velocity by a constant per iteration. That capped the fling at 60 fps on a
/// 120 Hz display, and because the damping was applied per *frame* rather than per
/// unit of time, the fling length changed with the refresh rate. This mirrors what
/// `UIScrollView` does: decay by elapsed time, advance on the display link.
@MainActor
final class MapDecelerator {

    /// `UIScrollView.DecelerationRate.normal`, expressed per millisecond.
    private let decelerationRate: CGFloat = 0.998

    /// Below this (points per second) the fling is over.
    private let minimumVelocity: CGFloat = 5

    /// Converts the frame's elapsed seconds into the millisecond base
    /// ``decelerationRate`` is expressed in.
    private static let millisecondsPerSecond: CGFloat = 1000

    /// ProMotion range the display link asks for: never below 60 Hz, up to 120 Hz,
    /// preferring the fastest so the fling is as smooth as the panel allows.
    private static let minimumFrameRate: Float = 60
    private static let maximumFrameRate: Float = 120
    private static let preferredFrameRate: Float = 120

    private var displayLink: CADisplayLink?
    private var velocity: CGPoint = .zero
    private var lastTimestamp: CFTimeInterval = 0

    private var onStep: ((CGSize) -> Void)?
    private var onFinish: (() -> Void)?

    /// Whether a fling is currently being animated.
    var isRunning: Bool { displayLink != nil }

    /// Starts a fling from the given pan velocity.
    ///
    /// Any running fling is cancelled first. A velocity below ``minimumVelocity`` in
    /// both axes finishes immediately, so callers always see `onFinish`.
    ///
    /// - Parameters:
    ///   - velocity: pan velocity in points per second.
    ///   - onStep: receives the translation for the elapsed frame.
    ///   - onFinish: called once the fling settles or is cancelled.
    func start(velocity: CGPoint,
               onStep: @escaping (CGSize) -> Void,
               onFinish: @escaping () -> Void) {

        stop()

        guard abs(velocity.x) > minimumVelocity || abs(velocity.y) > minimumVelocity else {
            onFinish()
            return
        }

        self.velocity = velocity
        self.onStep = onStep
        self.onFinish = onFinish
        self.lastTimestamp = 0

        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        // Opt into the full ProMotion range; needs CADisableMinimumFrameDuration
        // in Info.plist to go above 60 Hz.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Self.minimumFrameRate,
                                                        maximum: Self.maximumFrameRate,
                                                        preferred: Self.preferredFrameRate)
        link.add(to: .main, forMode: .common)

        displayLink = link
    }

    /// Cancels without calling `onFinish`.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onStep = nil
        onFinish = nil
        velocity = .zero
        lastTimestamp = 0
    }

    /// Advances the fling by one display frame.
    ///
    /// Decays the velocity by the time that actually elapsed rather than per frame, so
    /// the fling covers the same distance at 60 and at 120 Hz, and finishes once both
    /// axes drop below ``minimumVelocity``.
    ///
    /// - Parameter link: The display link driving the animation.
    @objc private func handleFrame(_ link: CADisplayLink) {

        // First tick only establishes the time base.
        guard lastTimestamp != 0 else {
            lastTimestamp = link.timestamp
            return
        }

        let elapsed = CGFloat(link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp

        guard elapsed > 0 else { return }

        let decay = pow(decelerationRate, elapsed * Self.millisecondsPerSecond)
        velocity.x *= decay
        velocity.y *= decay

        onStep?(CGSize(width: velocity.x * elapsed, height: velocity.y * elapsed))

        if abs(velocity.x) < minimumVelocity && abs(velocity.y) < minimumVelocity {
            let finish = onFinish
            stop()
            finish?()
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}
