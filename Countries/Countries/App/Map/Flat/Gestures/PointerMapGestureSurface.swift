//
//  PointerMapGestureSurface.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

import AppKit
import SwiftUI

/// The pointer implementation of ``MapGestureSurface``: scroll to pan, magnify to zoom, click
/// and double click to select.
///
/// - Note: The system's own scroll momentum is deliberately **ignored**. A trackpad sends a
///   second run of events after the fingers lift, with its own inertia curve; letting those
///   through as well as running ``MapDecelerator`` would decelerate the map twice, at two
///   different rates. Instead the momentum phase is dropped and the fling is handed to the
///   same decelerator the touch surface uses, so a Mac and an iPhone coast identically.
struct PointerMapGestureSurface: MapGestureSurface, NSViewRepresentable {

    // MARK: - Properties

    /// What to call as the gesture progresses.
    let handlers: MapGestureHandlers

    // MARK: - Life cycle

    /// - Parameter handlers: What to call as the gesture progresses.
    init(handlers: MapGestureHandlers) {
        self.handlers = handlers
    }

    // MARK: - NSViewRepresentable

    /// Builds the transparent view that receives the events.
    ///
    /// - Parameter context: Representable context; unused, the view holds the handlers itself.
    /// - Returns: A clear view that accepts scroll, magnify and mouse events.
    func makeNSView(context: Context) -> GestureView {
        GestureView(handlers: handlers)
    }

    /// Refreshes the handlers, which capture the current viewport and camera geometry.
    ///
    /// - Parameters:
    ///   - nsView: The view created by ``makeNSView(context:)``.
    ///   - context: Representable context; unused.
    func updateNSView(_ nsView: GestureView, context: Context) {
        nsView.handlers = handlers
    }

    // MARK: - Gesture view

    /// Receives the AppKit events and reports them in the map's own vocabulary.
    final class GestureView: NSView {

        // MARK: Constants

        /// Thresholds and conversions of the pointer gestures.
        private enum Metrics {

            /// Clicks that count as a double click.
            static let doubleClickCount = 2

            /// Seconds of scrolling that the final velocity is measured over.
            ///
            /// One frame at 60 Hz. Short enough to be the *current* speed rather than the
            /// average of the whole gesture, long enough not to be one stray event.
            static let velocityWindow: TimeInterval = 1.0 / 60

            /// Guards the division when two events arrive in the same instant.
            static let minimumTimeStep: TimeInterval = 0.001

            /// Scroll distance per notch for a mouse wheel, which reports no phase at all and
            /// therefore never begins or ends a pan.
            static let wheelStepFallback: CGFloat = 1
        }

        // MARK: State

        /// What to call as the gesture progresses.
        var handlers: MapGestureHandlers

        /// Whether a phased scroll is currently running, so the end can be reported once.
        private var isPanning = false

        /// The last scroll delta and when it arrived, for the final velocity.
        private var lastScrollDelta: CGSize = .zero
        private var lastScrollTime: TimeInterval = 0

        // MARK: Life cycle

        /// - Parameter handlers: What to call as the gesture progresses.
        init(handlers: MapGestureHandlers) {
            self.handlers = handlers
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used; this view is created in code only.")
        }

        override var isOpaque: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // MARK: Scrolling

        /// Turns a scroll into a pan.
        ///
        /// - Parameter event: The scroll event.
        override func scrollWheel(with event: NSEvent) {

            // The system's own inertia, dropped on purpose — see the note on the type.
            guard event.momentumPhase == [] else { return }

            let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)

            switch event.phase {
            case .began:
                beginPan()
            case .ended, .cancelled:
                endPan()
                return
            default:
                // A mouse wheel reports no phase. It still pans, it just never flings.
                break
            }

            guard delta != .zero else { return }

            recordScroll(delta)
            handlers.onPanChanged(delta)
        }

        /// Starts a pan, halting any inertia first.
        private func beginPan() {

            isPanning = true
            lastScrollDelta = .zero
            lastScrollTime = ProcessInfo.processInfo.systemUptime

            handlers.onTouchDown()
            handlers.onPanBegan()
        }

        /// Ends a pan, handing over the velocity that drives the fling.
        private func endPan() {

            guard isPanning else { return }

            isPanning = false
            handlers.onPanEnded(currentVelocity())
        }

        /// Remembers the latest scroll step for the velocity estimate.
        ///
        /// - Parameter delta: The step, in points.
        private func recordScroll(_ delta: CGSize) {

            lastScrollDelta = delta
            lastScrollTime = ProcessInfo.processInfo.systemUptime
        }

        /// The pan velocity in points per second, from the most recent step.
        ///
        /// - Returns: The velocity, or zero when the gesture has already gone still.
        private func currentVelocity() -> CGPoint {

            let elapsed = ProcessInfo.processInfo.systemUptime - lastScrollTime

            // Stale means the fingers rested before lifting, which is a deliberate stop.
            guard elapsed < Metrics.velocityWindow * 2 else { return .zero }

            let step = max(elapsed, Metrics.minimumTimeStep)

            return CGPoint(x: lastScrollDelta.width / step, y: lastScrollDelta.height / step)
        }

        // MARK: Magnifying

        /// Turns a pinch on the trackpad into a zoom around the pointer.
        ///
        /// - Parameter event: The magnification event.
        override func magnify(with event: NSEvent) {

            let center = convert(event.locationInWindow, from: nil)

            switch event.phase {
            case .began:
                handlers.onPinchBegan()
            case .ended, .cancelled:
                handlers.onPinchEnded()
            default:
                // AppKit reports the change as a delta around zero; the map wants a factor
                // around one, the same increment the touch surface sends.
                handlers.onPinchChanged(1 + event.magnification, center)
            }
        }

        // MARK: Clicking

        /// Reports the press, so a coasting map stops the moment the pointer lands.
        ///
        /// - Parameter event: The mouse event.
        override func mouseDown(with event: NSEvent) {
            handlers.onTouchDown()
        }

        /// Reports a click or a double click in view coordinates.
        ///
        /// - Parameter event: The mouse event.
        override func mouseUp(with event: NSEvent) {

            let point = convert(event.locationInWindow, from: nil)

            if event.clickCount >= Metrics.doubleClickCount {
                handlers.onDoubleTap(point)
                return
            }

            handlers.onTap(point)
        }
    }
}

#endif
