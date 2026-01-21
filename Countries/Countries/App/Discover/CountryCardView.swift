//
//  CountryCardView.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI

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
                    .black.opacity(0.15),
                    .black.opacity(0.35),
                    .black.opacity(0.60)
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
        VStack(alignment: .leading, spacing: 10) {

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
                    .foregroundStyle(.white) // explizit
            }

            if let nativeName = country.nativeName {
                Text(nativeName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)

            HStack {
                Text("Tap für Details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
