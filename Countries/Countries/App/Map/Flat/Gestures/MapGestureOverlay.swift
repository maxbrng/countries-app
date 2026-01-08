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
    
    var onPanBegan: () -> Void
    var onPanChanged: (CGSize) -> Void
    var onPanEnded: (CGPoint) -> Void

    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void

    var onDoubleTap: (CGPoint) -> Void
    var onTap: (CGPoint) -> Void

    init(
        onPanBegan: @escaping () -> Void,
        onPanChanged: @escaping (CGSize) -> Void,
        onPanEnded: @escaping (CGPoint) -> Void,
        onPinchBegan: @escaping () -> Void,
        onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
        onPinchEnded: @escaping () -> Void,
        onDoubleTap: @escaping (CGPoint) -> Void,
        onTap: @escaping (CGPoint) -> Void
    ) {
        self.onPanBegan = onPanBegan
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
        self.onPinchBegan = onPinchBegan
        self.onPinchChanged = onPinchChanged
        self.onPinchEnded = onPinchEnded
        self.onDoubleTap = onDoubleTap
        self.onTap = onTap
    }

    func makeUIView(context: Context) -> UIView {
        
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.minimumNumberOfTouches = 1
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator

        tap.require(toFail: doubleTap)

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
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

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        
        var onPanBegan: () -> Void
        var onPanChanged: (CGSize) -> Void
        var onPanEnded: (CGPoint) -> Void

        var onPinchBegan: () -> Void
        var onPinchChanged: (CGFloat, CGPoint) -> Void
        var onPinchEnded: () -> Void

        var onDoubleTap: (CGPoint) -> Void
        var onTap: (CGPoint) -> Void

        init(
            onPanBegan: @escaping () -> Void,
            onPanChanged: @escaping (CGSize) -> Void,
            onPanEnded: @escaping (CGPoint) -> Void,
            onPinchBegan: @escaping () -> Void,
            onPinchChanged: @escaping (CGFloat, CGPoint) -> Void,
            onPinchEnded: @escaping () -> Void,
            onDoubleTap: @escaping (CGPoint) -> Void,
            onTap: @escaping (CGPoint) -> Void
        ) {
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPinchBegan = onPinchBegan
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
            self.onDoubleTap = onDoubleTap
            self.onTap = onTap
        }

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

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            
            guard let view = recognizer.view else { return }
            
            onTap(recognizer.location(in: view))
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            
            guard let view = recognizer.view else { return }
            
            onDoubleTap(recognizer.location(in: view))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
