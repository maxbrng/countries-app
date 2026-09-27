//
//  CountryCardView.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import UIKit

// MARK: - Metrics

/// Layout values shared by the card and its badges.
///
/// The badges all use the same height and capsule padding so the bottom info bar lines up
/// regardless of which badge is shown.
private enum CardMetrics {

    /// Corner radius of the card, used for the clip shape and the hit test shape alike.
    static let cardCornerRadius: CGFloat = 36

    /// Inset between the card edge and its text content.
    static let contentPadding: CGFloat = 22

    /// Vertical spacing between the content blocks.
    static let contentSpacing: CGFloat = 12

    /// Keeps the text above background and gradient in the card's `ZStack`.
    static let contentZIndex: Double = 10

    /// Opacity stops of the readability gradient, top to bottom.
    static let readabilityGradientOpacities: [Double] = [0.4, 0.15, 0, 0.2, 0.5]

    /// Opacity of the neutral placeholder shown while no photo is available.
    static let placeholderOpacity: Double = 0.12

    /// Spacing between the flag and the country name.
    static let headerSpacing: CGFloat = 10

    /// Size of the flag in the card header.
    static let flagWidth: CGFloat = 40

    /// Height of the flag in the card header.
    static let flagHeight: CGFloat = 30

    /// Corner radius of the flag and of its border overlay.
    static let flagCornerRadius: CGFloat = 4

    /// Width of every hairline border on the card: flag, badges and chips.
    static let hairlineWidth: CGFloat = 1

    /// Extra spacing above the travel tag row.
    static let tagRowTopPadding: CGFloat = 2

    /// Spacing between the badges of the bottom info bar.
    static let infoBarSpacing: CGFloat = 10

    /// Vertical padding of the footer row.
    static let footerVerticalPadding: CGFloat = 8

    /// Uniform badge height, so every badge in the info bar has the same silhouette.
    static let badgeHeight: CGFloat = 32

    /// Spacing between icon and label inside a chip.
    static let chipContentSpacing: CGFloat = 6

    /// Spacing between the thermometer symbol and its label, and between tag chips.
    static let wideChipSpacing: CGFloat = 8

    /// Horizontal padding inside a capsule badge.
    static let badgeHorizontalPadding: CGFloat = 10

    /// Vertical padding of the small meta chip, which is not height-locked to the info bar.
    static let miniChipVerticalPadding: CGFloat = 6

    /// Horizontal padding of the small meta chip.
    static let miniChipHorizontalPadding: CGFloat = 8

    /// Opacity of the glass fill behind a badge.
    static let badgeGlassOpacity: Double = 0.75

    /// Opacity of the hairline around a capsule badge.
    static let badgeBorderOpacity: Double = 0.18

    /// Opacity of the hairline around the small meta chip.
    static let miniChipBorderOpacity: Double = 0.16

    /// Opacity of secondary white text on the photo background.
    static let secondaryTextOpacity: Double = 0.92

    /// Opacity of label text inside a badge.
    static let badgeTextOpacity: Double = 0.95

    /// Opacity of the euro symbols above the country's cost level.
    static let inactiveEuroOpacity: Double = 0.25

    /// Spacing between the euro symbols of the cost badge.
    static let euroSymbolSpacing: CGFloat = 2

    /// Opacity of the palette's secondary layer in the thermometer symbol.
    static let thermometerSecondaryOpacity: Double = 0.35

    /// Point size of the thermometer symbol.
    static let thermometerSymbolSize: CGFloat = 18
}

// MARK: - Card

/// Full-bleed country card used by the Discover stack: photo, name, travel tags and a bottom info
/// bar with climate, cost and safety.
///
/// The card renders at an explicit size instead of growing with its content, because the Discover
/// stack pages one card per viewport and needs the exact page height.
struct CountryCardView: View {

    /// The country the card describes.
    let country: Country

    /// Height the card is rendered at, set by the paging stack.
    let height: CGFloat

    /// Width the card is rendered at, set by the paging stack.
    let width: CGFloat

    /// Photo source; observed so the card redraws once an image URL resolves.
    @ObservedObject var service: PhotoService

    private let cardShape = RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius,
                                             style: .continuous)

    /// Neutral fill shown while there is no photo to display.
    private var placeholderBackground: Color {
        .black.opacity(CardMetrics.placeholderOpacity)
    }

    // MARK: - Body

    var body: some View {

        ZStack(alignment: .bottomLeading) {

            // 1) Background (always full size)
            background
                .frame(maxWidth: width, maxHeight: height)

            // 2) Readability overlay (gradient)
            LinearGradient(
                colors: CardMetrics.readabilityGradientOpacities.map { Color.black.opacity($0) },
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // 3) Content
            content
                .padding(CardMetrics.contentPadding)
                .zIndex(CardMetrics.contentZIndex) // text always on top
                .frame(maxWidth: width)
        }
        .frame(maxWidth: width)
        .frame(height: height)

        // This is the decisive part: one clip for image, gradient and text together.
        .clipShape(cardShape)
        .contentShape(cardShape)

        .task(id: country.iso2) {
            service.fetchImageIfNeeded(key: country.iso2, searchTerm: country.nameEnglish)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let url = service.url(for: country.iso2) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholderBackground
                        .overlay { ProgressView() }

                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill() // important: fill here, the card clips globally below

                case .failure:
                    placeholderBackground
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                        }

                @unknown default:
                    placeholderBackground
                }
            }
        } else if service.isLoading(country.iso2) {
            placeholderBackground
                .overlay { ProgressView() }
        } else if let error = service.errorMessage(for: country.iso2) {
            placeholderBackground
                .overlay {
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundStyle(.red)
                }
        } else {
            placeholderBackground
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: CardMetrics.contentSpacing) {

            header

            if let nativeName = country.nativeName {
                Text(nativeName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(CardMetrics.secondaryTextOpacity))
            }

            // Travel tags as icon chips
            if !country.travelTags.isEmpty {
                TravelTagRow(tags: country.travelTags)
                    .padding(.top, CardMetrics.tagRowTopPadding)
            }

            Spacer(minLength: 0)

            // Bottom info bar: climate + cost + optional (safety / duration / season)
            bottomInfoBar

            footer
                .padding(.vertical, CardMetrics.footerVerticalPadding)
        }
    }

    private var header: some View {
        HStack(spacing: CardMetrics.headerSpacing) {
            Image(country.iso2.lowercased())
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: CardMetrics.flagCornerRadius,
                                            style: .continuous))
                .scaledToFit()
                .overlay(
                    RoundedRectangle(cornerRadius: CardMetrics.flagCornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: CardMetrics.hairlineWidth)
                )
                .frame(width: CardMetrics.flagWidth, height: CardMetrics.flagHeight)

            Text(country.nameEnglish)
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }

    private var bottomInfoBar: some View {
        HStack(alignment: .center, spacing: CardMetrics.infoBarSpacing) {

            // Climate (thermometer symbol, colour and fill height)
            if let climate = country.climateTags.first {
                ClimateThermometerBadge(tag: climate)
            }

            // Cost, as a row of euro symbols
            CostEuroBadge(level: country.costLevel)

            Spacer(minLength: 0)

            MiniChip(icon: "shield",
                     text: country.safetyLevel.shortLabel,
                     tint: country.safetyLevel.tint)
        }
    }

    private var footer: some View {
        HStack {
            Text("Tap for details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(CardMetrics.secondaryTextOpacity))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(CardMetrics.secondaryTextOpacity))
        }
    }
}

// MARK: - TravelTag Icon Chips

/// Wrapping row of travel tag chips.
private struct TravelTagRow: View {

    /// The tags to show, in the order the country stores them.
    let tags: [TravelTag]

    var body: some View {

        FlowLayout(spacing: CardMetrics.wideChipSpacing) {
            ForEach(tags, id: \.self) { tag in
                TagIconChip(
                    icon: tag.icon,
                    label: tag.shortLabel
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single travel tag chip: SF Symbol plus short label.
private struct TagIconChip: View {

    /// SF Symbol name.
    let icon: String

    /// Short label shown next to the symbol.
    let label: String

    var body: some View {
        HStack(spacing: CardMetrics.chipContentSpacing) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(CardMetrics.badgeTextOpacity))
        .frame(height: CardMetrics.badgeHeight, alignment: .center)
        .capsuleBadgeStyle()
    }
}

// MARK: - Climate Thermometer (colour and fill height)

/// Climate badge that encodes the climate twice: in the thermometer's fill height and in its tint.
private struct ClimateThermometerBadge: View {

    /// The climate to visualise.
    let tag: ClimateTag

    var body: some View {
        HStack(spacing: CardMetrics.wideChipSpacing) {

            Image(systemName: tag.thermometerSymbol)
                .font(.system(size: CardMetrics.thermometerSymbolSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(tag.tint,
                                 .white.opacity(CardMetrics.thermometerSecondaryOpacity))

            Text(tag.shortLabel.capitalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(CardMetrics.badgeTextOpacity))
        }
        .frame(height: CardMetrics.badgeHeight, alignment: .center)
        .capsuleBadgeStyle()
    }
}

private extension ClimateTag {

    /// Upper bound of the thermometer's low fill range.
    static let thermometerLowUpperBound: CGFloat = 0.34

    /// Upper bound of the thermometer's medium fill range.
    static let thermometerMediumUpperBound: CGFloat = 0.67

    /// The thermometer symbol whose fill matches ``fillLevel``.
    var thermometerSymbol: String {
        // fillLevel is 0...1
        switch fillLevel {
        case ..<Self.thermometerLowUpperBound: return "thermometer.low"
        case ..<Self.thermometerMediumUpperBound: return "thermometer.medium"
        default: return "thermometer.high"
        }
    }
}

// MARK: - Cost Euro Badge

/// Cost badge that fills as many euro symbols as the country's cost level ranks.
private struct CostEuroBadge: View {

    /// The cost level to show.
    let level: CostLevel

    /// Number of euro symbols drawn, matching the number of ``CostLevel`` ranks.
    private static let rankCount = 5

    var body: some View {
        HStack(spacing: CardMetrics.euroSymbolSpacing) {
            ForEach(1...Self.rankCount, id: \.self) { rank in
                Text(verbatim: "€")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rank <= level.rawValue
                                     ? .white.opacity(CardMetrics.badgeTextOpacity)
                                     : .white.opacity(CardMetrics.inactiveEuroOpacity))
            }
        }
        .frame(height: CardMetrics.badgeHeight, alignment: .center)
        .capsuleBadgeStyle()
        .accessibilityLabel("Kostenlevel \(level.rawValue) von 5")
    }
}

// MARK: - Small chip for optional meta

/// Compact tinted chip for a single piece of metadata, for example the safety level.
private struct MiniChip: View {

    /// SF Symbol name.
    let icon: String

    /// Label shown next to the symbol.
    let text: String

    /// Tint applied to both symbol and label.
    let tint: Color

    var body: some View {
        HStack(spacing: CardMetrics.chipContentSpacing) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.vertical, CardMetrics.miniChipVerticalPadding)
        .padding(.horizontal, CardMetrics.miniChipHorizontalPadding)
        .background(
            Capsule(style: .continuous)
                .glassEffect(.clear, in: Capsule(style: .continuous))
                .opacity(CardMetrics.badgeGlassOpacity)
                .colorScheme(.light)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(CardMetrics.miniChipBorderOpacity),
                                lineWidth: CardMetrics.hairlineWidth)
                )
        )
    }
}

// MARK: - Mappings

private extension TravelTag {

    /// SF Symbol representing the tag.
    var icon: String {
        switch self {
        case .beach: return "sun.max"
        case .nature: return "leaf"
        case .hiking: return "figure.hiking"
        case .culture: return "building.columns"
        case .food: return "fork.knife"
        case .nightlife: return "sparkles"
        case .citytrip: return "building.2"
        case .relax: return "bed.double"
        case .adventure: return "mountain.2"
        case .skiing: return "snowflake"
        }
    }

    /// Chip label, short enough to survive the card's flow layout.
    var shortLabel: String {
        switch self {
        case .beach: return "Beach"
        case .nature: return "Nature"
        case .hiking: return "Hike"
        case .culture: return "Culture"
        case .food: return "Food"
        case .nightlife: return "Night"
        case .citytrip: return "City"
        case .relax: return "Relax"
        case .adventure: return "Adventure"
        case .skiing: return "Ski"
        }
    }
}

private extension ClimateTag {

    /// Badge label for the climate.
    var shortLabel: String {
        switch self {
        case .cold: return "Cold"
        case .mild: return "Mild"
        case .warm: return "Warm"
        case .tropical: return "Tropical"
        case .mixed: return "Mixed"
        }
    }

    /// Thermometer fill height, 0...1, which also picks the symbol variant.
    var fillLevel: CGFloat {
        switch self {
        case .cold: return 0.20
        case .mild: return 0.45
        case .warm: return 0.70
        case .tropical: return 0.92
        case .mixed: return 0.55
        }
    }

    /// Colour matching the climate.
    var tint: Color {
        // Resolve system colors as they appear in Dark Mode, regardless of current scheme
        darkModeResolved(.climateTint(for: self))
    }
}

private extension SafetyLevel {

    /// Badge label for the safety level.
    var shortLabel: String {
        switch self {
        case .verySafe: return "Very safe"
        case .safe: return "Safe"
        case .mixed: return "Mixed"
        case .risky: return "Risky"
        case .veryRisky: return "Very risky"
        }
    }

    /// Colour matching the safety level, from green for safe to red for risky.
    var tint: Color {
        // Resolve system colors as they appear in Dark Mode, regardless of current scheme
        darkModeResolved(.safetyTint(for: self))
    }
}

private extension TravelDuration {

    /// Compact day range for the duration.
    var shortLabel: String {
        switch self {
        case .weekend: return "Weekend"
        case .short: return "4–7d"
        case .medium: return "8–14d"
        case .long: return "15–30d"
        case .nomad: return "30+d"
        }
    }
}

// MARK: - Tint resolution

/// Resolves a system colour the way it appears in Dark Mode, independent of the current interface
/// style, so badge tints stay legible on the card's darkened photo background.
///
/// - Parameter uiColor: The system colour to resolve.
/// - Returns: The resolved colour.
private func darkModeResolved(_ uiColor: UIColor) -> Color {
    Color(uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
}

private extension UIColor {

    /// The unresolved system colour used for a climate tag.
    static func climateTint(for tag: ClimateTag) -> UIColor {
        switch tag {
        case .cold: return .cyan
        case .mild: return .systemGreen
        case .warm: return .systemOrange
        case .tropical: return .systemRed
        case .mixed: return .systemYellow
        }
    }

    /// The unresolved system colour used for a safety level.
    static func safetyTint(for level: SafetyLevel) -> UIColor {
        switch level {
        case .verySafe: return .systemGreen
        case .safe: return .systemMint
        case .mixed: return .systemYellow
        case .risky: return .systemOrange
        case .veryRisky: return .systemRed
        }
    }
}

// MARK: - Flow Layout

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

// MARK: - Capsule Badge Style Modifier

/// Shared capsule background for the card's badges: light glass with a hairline border.
private struct CapsuleBadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CardMetrics.badgeHorizontalPadding)
            .background(
                Capsule(style: .continuous)
                    .glassEffect(.clear, in: Capsule(style: .continuous))
                    .opacity(CardMetrics.badgeGlassOpacity)
                    .colorScheme(.light)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(CardMetrics.badgeBorderOpacity),
                                    lineWidth: CardMetrics.hairlineWidth)
                    )
            )
            .contentShape(Capsule(style: .continuous))
    }
}

private extension View {

    /// Applies ``CapsuleBadgeStyle``.
    func capsuleBadgeStyle() -> some View {
        self.modifier(CapsuleBadgeStyle())
    }
}
