//
//  MapGestureOverlay.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import UIKit

/// A thin UIKit bridge for "map-like" gestures with velocity (pan) and proper pinch center.
/// Keeping this separate makes the main SwiftUI view much smaller and testable.
struct MapGestureOverlay: UIViewRepresentable {

    // MARK: - Callbacks

    /// Fires the moment a finger lands, before any movement. A pan recogniser only
    /// begins once the touch actually moves, so without this a tap on a coasting
    /// map would not stop it - Apple Maps halts inertia on touch-down.
    var onTouchDown: () -> Void

    /// Fires when a pan starts, before the first translation is reported.
    var onPanBegan: () -> Void

    /// Reports the translation since the previous callback, not since the gesture
    /// started: the recogniser is reset to zero after every step.
    var onPanChanged: (CGSize) -> Void

    /// Fires when the pan ends or is cancelled, carrying the final velocity in points
    /// per second, which is what drives the fling.
    var onPanEnded: (CGPoint) -> Void

    /// Fires when a pinch starts, before the first scale change is reported.
    var onPinchBegan: () -> Void

    /// Reports the incremental scale factor and the pinch center in view coordinates;
    /// the scale is reset to one after every step.
    var onPinchChanged: (CGFloat, CGPoint) -> Void

    /// Fires when the pinch ends or is cancelled.
    var onPinchEnded: () -> Void

    /// Reports a double tap at the given point in view coordinates.
    var onDoubleTap: (CGPoint) -> Void

    /// Reports a single tap at the given point in view coordinates. Only fires once
    /// the double tap recogniser has failed.
    var onTap: (CGPoint) -> Void

    // MARK: - Constants

    /// Recogniser configuration. Named so the numbers in `makeUIView(context:)` read
    /// as intent rather than as bare counts.
    private enum Recognizers {
        /// A map pan follows one or two fingers; a third is not a pan any more.
        static let minimumPanTouches = 1
        static let maximumPanTouches = 2

        static let singleTapCount = 1
        static let doubleTapCount = 2

        /// Zero duration: the long press only reports the touch and never delays it.
        static let touchDownPressDuration: TimeInterval = 0
    }

    // MARK: - Initialization

    /// Creates the overlay.
    ///
    /// - Parameters:
    ///   - onTouchDown: Called as soon as a finger lands.
    ///   - onPanBegan: Called when a pan starts.
    ///   - onPanChanged: Called with the translation since the previous step.
    ///   - onPanEnded: Called with the final pan velocity in points per second.
    ///   - onPinchBegan: Called when a pinch starts.
    ///   - onPinchChanged: Called with the incremental scale and the pinch center.
    ///   - onPinchEnded: Called when a pinch ends.
    ///   - onDoubleTap: Called with the location of a double tap.
    ///   - onTap: Called with the location of a single tap.
    init(
        onTouchDown: @escaping () -> Void,
        onPanBegan: @escaping () -> Void,
        onPanChanged: @escaping (CGSize) -> Void,
        onPanEnded: @escaping (CGPoint) -> Void,
        onPinchBegan: @escaping () -> Void,
        onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
        onPinchEnded: @escaping () -> Void,
        onDoubleTap: @escaping (CGPoint) -> Void,
        onTap: @escaping (CGPoint) -> Void
    ) {
        self.onTouchDown = onTouchDown
        self.onPanBegan = onPanBegan
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
        self.onPinchBegan = onPinchBegan
        self.onPinchChanged = onPinchChanged
        self.onPinchEnded = onPinchEnded
        self.onDoubleTap = onDoubleTap
        self.onTap = onTap
    }

    // MARK: - UIViewRepresentable

    /// Builds the transparent view that carries the gesture recognisers.
    ///
    /// - Parameter context: Representable context holding the coordinator.
    /// - Returns: A clear view with pan, pinch, tap, double tap and touch-down
    ///   recognisers attached.
    func makeUIView(context: Context) -> UIView {

        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = Recognizers.maximumPanTouches
        pan.minimumNumberOfTouches = Recognizers.minimumPanTouches
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = Recognizers.singleTapCount
        tap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = Recognizers.doubleTapCount
        doubleTap.delegate = context.coordinator

        tap.require(toFail: doubleTap)

        // Zero-duration long press = "a finger touched down". Never delays or
        // cancels the real gestures, it only reports the touch.
        let touchDown = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleTouchDown(_:)))
        touchDown.minimumPressDuration = Recognizers.touchDownPressDuration
        touchDown.cancelsTouchesInView = false
        touchDown.delaysTouchesBegan = false
        touchDown.delaysTouchesEnded = false
        touchDown.delegate = context.coordinator
        view.addGestureRecognizer(touchDown)

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)

        return view
    }

    /// The coordinator is created once but the closures capture the current
    /// viewport, worldRect and fitScale. Without refreshing them here every
    /// gesture would keep operating on the geometry of the very first layout.
    ///
    /// - Parameters:
    ///   - uiView: The view created by ``makeUIView(context:)``.
    ///   - context: Representable context holding the coordinator.
    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTouchDown = onTouchDown
        coordinator.onPanBegan = onPanBegan
        coordinator.onPanChanged = onPanChanged
        coordinator.onPanEnded = onPanEnded
        coordinator.onPinchBegan = onPinchBegan
        coordinator.onPinchChanged = onPinchChanged
        coordinator.onPinchEnded = onPinchEnded
        coordinator.onDoubleTap = onDoubleTap
        coordinator.onTap = onTap
    }

    /// Creates the recogniser target, seeded with the current callbacks.
    ///
    /// - Returns: The ``Coordinator`` that stays alive for this view's lifetime.
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTouchDown: onTouchDown,
            onPanBegan: onPanBegan,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded,
            onPinchBegan: onPinchBegan,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded,
            onDoubleTap: onDoubleTap,
            onTap: onTap
        )
    }

    // MARK: - Coordinator

    /// Target of every recogniser and the delegate that lets them run together.
    ///
    /// - Note: The callbacks are mutable because ``updateUIView(_:context:)`` replaces
    ///   them on every SwiftUI update; the coordinator itself is created only once.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        // MARK: Callbacks

        /// Called as soon as a finger lands, before any movement.
        var onTouchDown: () -> Void

        /// Called when a pan starts.
        var onPanBegan: () -> Void

        /// Called with the translation since the previous step.
        var onPanChanged: (CGSize) -> Void

        /// Called with the final pan velocity in points per second.
        var onPanEnded: (CGPoint) -> Void

        /// Called when a pinch starts.
        var onPinchBegan: () -> Void

        /// Called with the incremental scale and the pinch center.
        var onPinchChanged: (CGFloat, CGPoint) -> Void

        /// Called when a pinch ends.
        var onPinchEnded: () -> Void

        /// Called with the location of a double tap.
        var onDoubleTap: (CGPoint) -> Void

        /// Called with the location of a single tap.
        var onTap: (CGPoint) -> Void

        // MARK: Initialization

        /// Creates the coordinator with the callbacks currently held by the overlay.
        ///
        /// - Parameters:
        ///   - onTouchDown: Called as soon as a finger lands.
        ///   - onPanBegan: Called when a pan starts.
        ///   - onPanChanged: Called with the translation since the previous step.
        ///   - onPanEnded: Called with the final pan velocity in points per second.
        ///   - onPinchBegan: Called when a pinch starts.
        ///   - onPinchChanged: Called with the incremental scale and the pinch center.
        ///   - onPinchEnded: Called when a pinch ends.
        ///   - onDoubleTap: Called with the location of a double tap.
        ///   - onTap: Called with the location of a single tap.
        init(
            onTouchDown: @escaping () -> Void,
            onPanBegan: @escaping () -> Void,
            onPanChanged: @escaping (CGSize) -> Void,
            onPanEnded: @escaping (CGPoint) -> Void,
            onPinchBegan: @escaping () -> Void,
            onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
            onPinchEnded: @escaping () -> Void,
            onDoubleTap: @escaping (CGPoint) -> Void,
            onTap: @escaping (CGPoint) -> Void
        ) {
            self.onTouchDown = onTouchDown
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPinchBegan = onPinchBegan
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
            self.onDoubleTap = onDoubleTap
            self.onTap = onTap
        }

        // MARK: Gesture handlers

        /// Reports the touch-down, ignoring every later state of the long press.
        ///
        /// - Parameter recognizer: The zero-duration long press recogniser.
        @objc func handleTouchDown(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onTouchDown()
        }

        /// Translates pan states into the overlay's callbacks.
        ///
        /// - Parameter recognizer: The pan recogniser.
        /// - Note: The translation is reset after every `.changed` step, so callers
        ///   receive increments instead of an ever-growing offset.
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {

            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                onPanBegan()
            case .changed:
                let translation = recognizer.translation(in: view)
                onPanChanged(CGSize(width: translation.x, height: translation.y))
                recognizer.setTranslation(.zero, in: view)
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: view)
                onPanEnded(CGPoint(x: velocity.x, y: velocity.y))
            default:
                break
            }
        }

        /// Translates pinch states into the overlay's callbacks.
        ///
        /// - Parameter recognizer: The pinch recogniser.
        /// - Note: The scale is reset after every `.changed` step, so callers receive
        ///   incremental factors around one.
        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {

            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                onPinchBegan()

            case .changed:
                let center = recognizer.location(in: view)
                onPinchChanged(recognizer.scale, center)
                recognizer.scale = 1

            case .ended, .cancelled, .failed:
                onPinchEnded()

            default:
                break
            }
        }

        /// Forwards a single tap in view coordinates.
        ///
        /// - Parameter recognizer: The single tap recogniser.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {

            guard let view = recognizer.view else { return }

            onTap(recognizer.location(in: view))
        }

        /// Forwards a double tap in view coordinates.
        ///
        /// - Parameter recognizer: The double tap recogniser.
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {

            guard let view = recognizer.view else { return }

            onDoubleTap(recognizer.location(in: view))
        }

        // MARK: UIGestureRecognizerDelegate

        /// Lets every recogniser on the overlay run alongside every other one, which is
        /// what makes panning while pinching feel like a map rather than a fight.
        ///
        /// - Parameters:
        ///   - gestureRecognizer: The recogniser asking for permission.
        ///   - otherGestureRecognizer: The recogniser it would run alongside.
        /// - Returns: Always `true`.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
