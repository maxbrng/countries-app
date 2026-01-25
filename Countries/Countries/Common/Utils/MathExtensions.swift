//
//  MathExtensions.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

nonisolated extension Comparable {
    func clamped(_ minValue: Self, _ maxValue: Self) -> Self {
        min(max(self, minValue), maxValue)
    }
}

nonisolated extension CGRect {
    func clampedToUnit() -> CGRect {
        let x0 = max(0, min(1, minX))
        let y0 = max(0, min(1, minY))
        let x1 = max(0, min(1, maxX))
        let y1 = max(0, min(1, maxY))
        return CGRect(x: x0, y: y0, width: max(0.0001, x1 - x0), height: max(0.0001, y1 - y0))
    }
}

nonisolated extension CGFloat {
    static func log2(_ x: CGFloat) -> CGFloat {
        CGFloat(Darwin.log2(Double(x)))
    }
}
