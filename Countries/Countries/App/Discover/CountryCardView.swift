//
//  CountryCardView.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import UIKit

struct CountryCardView: View {
    
    let country: Country
    let height: CGFloat
    let width: CGFloat
    @ObservedObject var service: PhotoService
    
    private let cardShape = RoundedRectangle(cornerRadius: 36, style: .continuous)
    
    var body: some View {
        
        ZStack(alignment: .bottomLeading) {
            
            // 1) Background (immer full size)
            background
                .frame(maxWidth: width, maxHeight: height)
            
            // 2) Lesbarkeits-Overlay (Gradient)
            LinearGradient(
                colors: [
                    .black.opacity(0.4),
                    .black.opacity(0.15),
                    .black.opacity(0),
                    .black.opacity(0.2),
                    .black.opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // 3) Content
            content
                .padding(22)
                .zIndex(10) // Text immer oben
                .frame(maxWidth: width)
        }
        .frame(maxWidth: width)
        .frame(height: height)
        
        // ✅ das ist der entscheidende Teil:
        .clipShape(cardShape)       // clippt ALLES (Bild + Gradient + Text)
        .contentShape(cardShape)
        
        .task(id: country.iso2) {
            service.fetchImageIfNeeded(key: country.iso2, searchTerm: country.nameEnglish)
        }
    }
    
    @ViewBuilder
    private var background: some View {
        if let url = service.url(for: country.iso2) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color.black.opacity(0.12)
                        .overlay { ProgressView() }

                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill() // wichtig: Fill + später globales Clip
                    
                case .failure:
                    Color.black.opacity(0.12)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                        }
                    
                @unknown default:
                    Color.black.opacity(0.12)
                }
            }
        } else if service.isLoading(country.iso2) {
            Color.black.opacity(0.12)
                .overlay { ProgressView() }
        } else if let error = service.errorMessage(for: country.iso2) {
            Color.black.opacity(0.12)
                .overlay {
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundStyle(.red)
                }
        } else {
            Color.black.opacity(0.12)
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            header
            
            if let nativeName = country.nativeName {
                Text(nativeName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            
            // TravelTags als Icon-Chips
            if !country.travelTags.isEmpty {
                TravelTagRow(tags: country.travelTags)
                    .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
            
            // Bottom-Info-Bar: Klima + Kosten + optional (Safety/Duration/Season)
            bottomInfoBar
            
            footer
                .padding(.vertical, 8)
        }
    }
    
    private var header: some View {
        HStack(spacing: 10) {
            Image(country.iso2.lowercased())
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .scaledToFit()
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .frame(width: 40, height: 30)
            
            Text(country.nameEnglish)
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }
    
    private var bottomInfoBar: some View {
        HStack(alignment: .center, spacing: 10) {
            
            // Climate (Thermometer + Farbe + “Füllhöhe”)
            ClimateThermometerBadge(tag: country.climateTags[0])
            
            // Costs (€€€..)
            CostEuroBadge(level: country.costLevel)
            
            Spacer(minLength: 0)
            
            MiniChip(icon: "shield", text: country.safetyLevel.shortLabel, tint: country.safetyLevel.tint)
        }
    }
    
    private var footer: some View {
        HStack {
            Text("Tap for details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

// MARK: - TravelTag Icon Chips

private struct TravelTagRow: View {
    let tags: [TravelTag]
    
    var body: some View {
        
        FlowLayout(spacing: 8) {
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


private struct TagIconChip: View {
    let icon: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.95))
        .frame(height: 32, alignment: .center)
        .modifier(CapsuleBadgeStyle())
    }
}

// MARK: - Climate Thermometer (Farbe + Füllhöhe)

private struct ClimateThermometerBadge: View {
    let tag: ClimateTag

    var body: some View {
        HStack(spacing: 8) {

            Image(systemName: tag.thermometerSymbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(tag.tint, .white.opacity(0.35))

            Text(tag.shortLabel.capitalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(height: 32, alignment: .center)
        .modifier(CapsuleBadgeStyle())
    }
}

private extension ClimateTag {
    var thermometerSymbol: String {
        // fillLevel ist 0...1
        switch fillLevel {
        case ..<0.34: return "thermometer.low"
        case ..<0.67: return "thermometer.medium"
        default:      return "thermometer.high"
        }
    }
}

// MARK: - Cost Euro Badge (€€€..)

private struct CostEuroBadge: View {
    let level: CostLevel
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Text("€")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(i <= level.rawValue ? .white.opacity(0.95) : .white.opacity(0.25))
            }
        }
        .frame(height: 32, alignment: .center)
        .modifier(CapsuleBadgeStyle())
        .accessibilityLabel("Kostenlevel \(level.rawValue) von 5")
    }
}

// MARK: - Small chip for optional meta

private struct MiniChip: View {
    let icon: String
    let text: String
    let tint: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            Capsule(style: .continuous)
                .glassEffect(.clear, in: Capsule(style: .continuous)).opacity(0.75)
                .colorScheme(.light)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

// MARK: - Mappings

private extension TravelTag {
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
    var shortLabel: String {
        switch self {
        case .cold: return "Cold"
        case .mild: return "Mild"
        case .warm: return "Warm"
        case .tropical: return "Tropical"
        case .mixed: return "Mixed"
        }
    }
    
    /// “Thermometer-Füllhöhe”
    var fillLevel: CGFloat {
        switch self {
        case .cold: return 0.20
        case .mild: return 0.45
        case .warm: return 0.70
        case .tropical: return 0.92
        case .mixed: return 0.55
        }
    }
    
    /// Farbe entsprechend Klima
    var tint: Color {
        // Resolve system colors as they appear in Dark Mode, regardless of current scheme
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        switch self {
        case .cold:
            return Color(UIColor.cyan.resolvedColor(with: darkTrait))
        case .mild:
            return Color(UIColor.systemGreen.resolvedColor(with: darkTrait))
        case .warm:
            return Color(UIColor.systemOrange.resolvedColor(with: darkTrait))
        case .tropical:
            return Color(UIColor.systemRed.resolvedColor(with: darkTrait))
        case .mixed:
            return Color(UIColor.systemYellow.resolvedColor(with: darkTrait))
        }
    }
}

// Optional: nur falls du Safety/Duration wirklich hast:
private extension SafetyLevel {
    var shortLabel: String {
        switch self {
        case .verySafe: return "Very safe"
        case .safe: return "Safe"
        case .mixed: return "Mixed"
        case .risky: return "Risky"
        case .veryRisky: return "Very risky"
        }
    }
    
    var tint: Color {
        // Resolve system colors as they appear in Dark Mode, regardless of current scheme
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        switch self {
        case .verySafe:
            return Color(UIColor.systemGreen.resolvedColor(with: darkTrait))
        case .safe:
            return Color(UIColor.systemMint.resolvedColor(with: darkTrait))
        case .mixed:
            return Color(UIColor.systemYellow.resolvedColor(with: darkTrait))
        case .risky:
            return Color(UIColor.systemOrange.resolvedColor(with: darkTrait))
        case .veryRisky:
            return Color(UIColor.systemRed.resolvedColor(with: darkTrait))
        }
    }
}

private extension TravelDuration {
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


struct FlowLayout: Layout {
    
    var spacing: CGFloat = 8
    
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
// MARK: - Capsule Badge Style Modifier

private struct CapsuleBadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .glassEffect(.clear, in: Capsule(style: .continuous)).opacity(0.75)
                    .colorScheme(.light)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .contentShape(Capsule(style: .continuous))
    }
}

private extension View {
    func capsuleBadgeStyle() -> some View {
        self.modifier(CapsuleBadgeStyle())
    }
}

