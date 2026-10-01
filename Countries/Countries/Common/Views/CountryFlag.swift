//
//  CountryFlag.swift
//  Countries
//
//  Created by Max Breuning on 01.10.26.
//

import SwiftUI

/// One country's flag, drawn from the bundled asset named after its ISO2 code.
///
/// The rounded corners and the hairline border are part of what a flag is here, not decoration
/// belonging to one screen: several flags of different proportions sitting next to each other
/// only read as a set when they share them. Keeping that in one place is what stops the country
/// list and the dashboard from drifting apart.
struct CountryFlag: View {

    // MARK: - Layout

    /// Aspect ratio every flag is drawn at, wider than tall as flags almost always are.
    ///
    /// Exposed because a caller laying several flags out side by side has to know how wide
    /// one is in order to overlap them.
    static let aspectRatio: CGFloat = 4.0 / 3.0

    /// Corner radius and border, scaled with the flag so a small one is not over-rounded.
    private enum Layout {

        /// Corner radius as a share of the flag's height.
        static let cornerRadiusShare: CGFloat = 0.13

        /// Width of the hairline that separates a pale flag from a pale background.
        static let borderWidth: CGFloat = 1
    }

    // MARK: - Properties

    /// ISO2 code of the country, in either case.
    let iso2: String

    /// Height the flag is drawn at. Its width follows from the aspect ratio.
    let height: CGFloat

    // MARK: - Init

    /// - Parameters:
    ///   - iso2: ISO2 code of the country, in either case.
    ///   - height: Height in points. Defaults to 30, the size the country list uses.
    init(iso2: String, height: CGFloat = 30) {
        self.iso2 = iso2
        self.height = height
    }

    // MARK: - Body

    var body: some View {

        let cornerRadius = height * Layout.cornerRadiusShare

        Image(iso2.lowercased())
            .resizable()
            .scaledToFill()
            .frame(width: height * Self.aspectRatio, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.quaternary, lineWidth: Layout.borderWidth)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 8) {
        CountryFlag(iso2: "de")
        CountryFlag(iso2: "jp", height: 20)
        CountryFlag(iso2: "br", height: 14)
    }
    .padding()
}
