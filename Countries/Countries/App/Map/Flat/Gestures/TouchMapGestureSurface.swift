//
//  TouchMapGestureSurface.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// The touch implementation of ``MapGestureSurface``: pan with velocity, pinch with a proper
/// centre, single and double tap, and a touch-down report the pan recogniser cannot give.
struct TouchMapGestureSurface: MapGestureSurface, UIViewRepresentable {

    // MARK: - Constants

    /// Recogniser configuration. Named so the numbers in ``makeUIView(context:)`` read as
    /// intent rather than as bare counts.
    private enum Recognizers {
        /// A map pan follows one or two fingers; a third is not a pan any more.
        static let minimumPanTouches = 1
        static let maximumPanTouches = 2

        static let singleTapCount = 1
        static let doubleTapCount = 2

        /// Zero duration: the long press only reports the touch and never delays it.
        static let touchDownPressDuration: TimeInterval = 0
    }

    // MARK: - Properties

    /// What to call as the gesture progresses.
    let handlers: MapGestureHandlers

    // MARK: - Life cycle

    /// - Parameter handlers: What to call as the gesture progresses.
    init(handlers: MapGestureHandlers) {
        self.handlers = handlers
    }

    // MARK: - UIViewRepresentable

    /// Builds the transparent view that carries the gesture recognisers.
    ///
    /// - Parameter context: Representable context holding the coordinator.
    /// - Returns: A clear view with pan, pinch, tap, double tap and touch-down recognisers.
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

        // Zero-duration long press = "a finger touched down". Never delays or cancels the real
        // gestures, it only reports the touch.
        let touchDown = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTouchDown(_:))
        )
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

    /// The coordinator is created once but the handlers capture the current viewport,
    /// worldRect and fitScale. Without refreshing them here every gesture would keep operating
    /// on the geometry of the very first layout.
    ///
    /// - Parameters:
    ///   - uiView: The view created by ``makeUIView(context:)``.
    ///   - context: Representable context holding the coordinator.
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.handlers = handlers
    }

    /// Creates the recogniser target, seeded with the current handlers.
    ///
    /// - Returns: The ``Coordinator`` that stays alive for this view's lifetime.
    func makeCoordinator() -> Coordinator {
        Coordinator(handlers: handlers)
    }

    // MARK: - Coordinator

    /// Target of every recogniser and the delegate that lets them run together.
    ///
    /// - Note: ``handlers`` is mutable because ``updateUIView(_:context:)`` replaces it on
    ///   every SwiftUI update; the coordinator itself is created only once.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        /// What to call as the gesture progresses.
        var handlers: MapGestureHandlers

        /// - Parameter handlers: The handlers held by the surface at creation time.
        init(handlers: MapGestureHandlers) {
            self.handlers = handlers
        }

        // MARK: Gesture handlers

        /// Reports the touch-down, ignoring every later state of the long press.
        ///
        /// - Parameter recognizer: The zero-duration long press recogniser.
        @objc func handleTouchDown(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            handlers.onTouchDown()
        }

        /// Translates pan states into the handlers.
        ///
        /// - Parameter recognizer: The pan recogniser.
        /// - Note: The translation is reset after every `.changed` step, so callers receive
        ///   increments instead of an ever-growing offset.
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {

            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                handlers.onPanBegan()
            case .changed:
                let translation = recognizer.translation(in: view)
                handlers.onPanChanged(CGSize(width: translation.x, height: translation.y))
                recognizer.setTranslation(.zero, in: view)
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: view)
                handlers.onPanEnded(CGPoint(x: velocity.x, y: velocity.y))
            default:
                break
            }
        }

        /// Translates pinch states into the handlers.
        ///
        /// - Parameter recognizer: The pinch recogniser.
        /// - Note: The scale is reset after every `.changed` step, so callers receive
        ///   incremental factors around one.
        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {

            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                handlers.onPinchBegan()

            case .changed:
                let center = recognizer.location(in: view)
                handlers.onPinchChanged(recognizer.scale, center)
                recognizer.scale = 1

            case .ended, .cancelled, .failed:
                handlers.onPinchEnded()

            default:
                break
            }
        }

        /// Forwards a single tap in view coordinates.
        ///
        /// - Parameter recognizer: The single tap recogniser.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {

            guard let view = recognizer.view else { return }

            handlers.onTap(recognizer.location(in: view))
        }

        /// Forwards a double tap in view coordinates.
        ///
        /// - Parameter recognizer: The double tap recogniser.
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {

            guard let view = recognizer.view else { return }

            handlers.onDoubleTap(recognizer.location(in: view))
        }

        // MARK: UIGestureRecognizerDelegate

        /// Lets every recogniser on the surface run alongside every other one, which is what
        /// makes panning while pinching feel like a map rather than a fight.
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

#endif
