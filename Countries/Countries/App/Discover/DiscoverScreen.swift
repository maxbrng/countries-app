//
//  DiscoverScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import SwiftData

/// The Discover tab: a full-screen, paging stack of recommended countries.
///
/// Scoring itself lives in ``DiscoverViewModel``, which only recomputes when the queried countries
/// or preferences actually change. The screen additionally preloads the card photos in throttled
/// batches so scrolling does not start a burst of requests.
struct DiscoverScreen: View {

    // MARK: - Environment and queries

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Country.iso2) private var allCountries: [Country]
    @Query(sort: \Trip.startDate, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \UserPreferences.updatedAt, order: .reverse) private var allPreferences: [UserPreferences]

    // MARK: - State

    @State private var viewModel = DiscoverViewModel()
    @StateObject private var service = PhotoService()
    @State private var algoSettingsSheet = false

    // MARK: - Constants

    /// Card and stack geometry.
    /// Marked `nonisolated` because the `visualEffect` closure is `@Sendable`; these are
    /// immutable value constants, so reading them off the main actor is safe.
    private nonisolated enum Layout {

        /// Inset subtracted from the available width and height to get the card size.
        static let cardInset: CGFloat = 40

        /// Corner radius of the card and of its glass effect.
        static let cardCornerRadius: CGFloat = 36

        /// Horizontal padding of the scrolling stack.
        static let stackHorizontalPadding: CGFloat = 16

        /// How much a card shrinks at the edge of the viewport, as a fraction of its size.
        static let maxScaleReduction: CGFloat = 0.05

        /// How much a card fades at the edge of the viewport, as a fraction of full opacity.
        static let maxOpacityReduction: CGFloat = 0.25
    }

    /// Photo preloading budget.
    private enum Preload {

        /// Number of leading cards whose photos are requested immediately.
        static let eagerCardCount = 6

        /// Number of cards per throttled follow-up batch.
        static let batchSize = 10

        /// Pause between two follow-up batches, to keep the API cooldown out of reach.
        static let batchPause: Duration = .milliseconds(200)
    }

    // MARK: - Derived state

    private var preferences: UserPreferences? { allPreferences.first }

    private var hasMarkedCountries: Bool {
        allCountries.contains { $0.status != .none }
    }

    // MARK: - Body

    var body: some View {

        Group {
            if viewModel.recommendations.isEmpty {
                emptyState
            } else {
                cardStack
            }
        }
        .navigationTitle("Recommendations")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    algoSettingsSheet.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $algoSettingsSheet) {
            AlgoSettingsSheetView()
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: Country.self) { country in
            CountryDetailsView(country: country)
        }
        .onAppear { refreshRecommendations() }
        .onChange(of: allCountries) { _, _ in refreshRecommendations() }
        .onChange(of: allPreferences) { _, _ in refreshRecommendations() }
        .task(id: viewModel.recommendations.count) {
            await preloadImages()
        }
        .onDisappear {
            service.cancelAll()
        }
    }

    // MARK: - Card stack

    private var cardStack: some View {

        GeometryReader { geo in

            let cardHeight = geo.size.height - Layout.cardInset
            let cardWidth = geo.size.width - Layout.cardInset

            ScrollView(.vertical) {

                LazyVStack(spacing: 0) {

                    ForEach(viewModel.recommendedCountries) { country in

                        NavigationLink(value: country) {

                            CountryCardView(country: country,
                                            height: cardHeight,
                                            width: cardWidth,
                                            service: service)
                            .glassEffect(
                                .regular.interactive(),
                                in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius,
                                                     style: .continuous)
                            )
                            .frame(width: cardWidth, height: cardHeight)
                            .containerRelativeFrame(.vertical, count: 1, spacing: 0)
                            .visualEffect { content, proxy in
                                // Progress is 0 for the centred card and 1 at the viewport edge.
                                let frame = proxy.frame(in: .scrollView)
                                let bounds = proxy.bounds(of: .scrollView)
                                let center = bounds?.midY ?? 0
                                let distance = abs(frame.midY - center)
                                let maxDistance = (bounds?.height ?? 1) / 2
                                let progress = min(distance / maxDistance, 1)
                                return content
                                    .scaleEffect(1.0 - (Layout.maxScaleReduction * progress),
                                                 anchor: .center)
                                    .opacity(1.0 - (Layout.maxOpacityReduction * progress))
                            }
                        }
                        .buttonStyle(.plain)
                        .scrollTargetLayout()
                    }
                }
                .padding(.horizontal, Layout.stackHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .edgesIgnoringSafeArea(.all)
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {

        if hasMarkedCountries {
            ContentUnavailableView {
                Label("No recommendations", systemImage: "binoculars")
            } description: {
                Text("Your filters rule out every remaining country. Loosen the budget or safety limits in the algorithm settings.")
            } actions: {
                Button("Algorithm settings") { algoSettingsSheet = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Nothing to go on yet", systemImage: "map")
            } description: {
                Text("Mark a few countries as visited or add them to your wishlist. Recommendations are derived from your travel history.")
            }
        }
    }

    // MARK: - Data

    /// Hands the current queries to the view model, which decides whether scoring has to run.
    private func refreshRecommendations() {
        viewModel.updateIfNeeded(countries: allCountries,
                                 trips: allTrips,
                                 preferences: preferences)
    }

    /// Loads the first cards eagerly, the rest in throttled batches.
    private func preloadImages() async {

        let countries = viewModel.recommendedCountries
        guard !countries.isEmpty else { return }

        let eagerCount = min(Preload.eagerCardCount, countries.count)
        service.preload(countries: Array(countries.prefix(eagerCount)))

        var index = eagerCount
        while index < countries.count {
            if Task.isCancelled { return }
            let upperBound = min(index + Preload.batchSize, countries.count)
            service.preload(countries: Array(countries[index..<upperBound]))
            index = upperBound
            try? await Task.sleep(for: Preload.batchPause)
        }
    }
}
