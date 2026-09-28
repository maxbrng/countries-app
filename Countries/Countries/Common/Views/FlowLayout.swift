//
//  FlowLayout.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Layout that places its subviews in a row and wraps to the next line when the proposed width runs
/// out, which is what the travel tag chips need.
struct FlowLayout: Layout {

    /// Gap between two subviews, horizontally and between rows. Defaults to `8`.
    var spacing: CGFloat = 8

    /// Reports the size the wrapped rows need.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size; an unspecified width is treated as unbounded.
    ///   - subviews: The subviews to place.
    ///   - cache: Unused.
    /// - Returns: The full proposed width and the height of all resulting rows.
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {

        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    /// Places the subviews row by row, wrapping at the trailing edge of `bounds`.
    ///
    /// - Parameters:
    ///   - bounds: The region to place the subviews in.
    ///   - proposal: The proposed size; each subview is placed at its own ideal size instead.
    ///   - subviews: The subviews to place.
    ///   - cache: Unused.
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
