//
//  TripUndoBanner.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftUI

/// Spacings and sizes of ``TripUndoBanner``.
private enum TripUndoBannerLayout {

    /// Spacing between the message and the undo button.
    static let contentSpacing: CGFloat = 12

    /// Horizontal padding inside the banner.
    static let horizontalPadding: CGFloat = 16

    /// Vertical padding inside the banner.
    static let verticalPadding: CGFloat = 12

    /// Corner radius of the banner.
    static let cornerRadius: CGFloat = 22

    /// Distance from the bottom edge of the safe area.
    static let bottomInset: CGFloat = 12
}

/// The short-lived offer to undo a trip deletion.
///
/// Deliberately not a trash bin: 1.0 has none. A bin is a second place where trips live and a
/// second thing to keep in sync, and it moves the decision from "now, while I still remember
/// what I did" to "later, when I have forgotten".
struct TripUndoBanner: View {

    // MARK: - Properties

    /// Title of the trip that was deleted.
    let tripTitle: String

    /// Puts the trip back.
    let onUndo: () -> Void

    // MARK: - Body

    var body: some View {

        HStack(spacing: TripUndoBannerLayout.contentSpacing) {

            Text("“\(tripTitle)” deleted")
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, TripUndoBannerLayout.horizontalPadding)
        .padding(.vertical, TripUndoBannerLayout.verticalPadding)
        .glassEffect(.regular.interactive(),
                     in: .rect(cornerRadius: TripUndoBannerLayout.cornerRadius))
        .padding(.horizontal)
        .padding(.bottom, TripUndoBannerLayout.bottomInset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    TripUndoBanner(tripTitle: "Summer in Spain", onUndo: {})
}
