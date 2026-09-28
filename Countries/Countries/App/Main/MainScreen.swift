//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import SwiftData

/// Root screen of the "Countries" tab: a tappable world-map preview, the visit statistics
/// and a card summarising the visited and wishlisted countries.
///
/// - Note: The screen owns no navigation state of its own; it appends ``AppRoute`` values to
///   the shared path handed in by ``RootTabView``.
struct MainScreen: View {

    // MARK: - Constants

    /// Spacings, radii and sizes used by this screen.
    private enum Layout {
        /// Vertical spacing between map preview, statistics and country card.
        static let stackSpacing: CGFloat = 40
        static let screenHorizontalPadding: CGFloat = 20
        /// Width / height ratio of the map preview.
        static let mapPreviewAspectRatio: CGFloat = 1.8
        static let mapPreviewCornerRadius: CGFloat = 40
        static let cardCornerRadius: CGFloat = 36
        static let cardVerticalPadding: CGFloat = 20
        static let cardHorizontalPadding: CGFloat = 24
        /// Vertical spacing between the card's title, its columns and the detail link.
        static let cardContentSpacing: CGFloat = 16
        /// Horizontal spacing between the "Visited" and "On Wishlist" columns.
        static let cardColumnSpacing: CGFloat = 24
        static let previewListSpacing: CGFloat = 8
        /// Horizontal spacing between the count and its caption.
        static let countLabelSpacing: CGFloat = 6
        /// Vertical spacing between two country rows of a column.
        static let countryRowSpacing: CGFloat = 6
        /// Horizontal spacing between a flag and a country name.
        static let flagLabelSpacing: CGFloat = 8
        static let flagCornerRadius: CGFloat = 2
        static let flagBorderWidth: CGFloat = 1
        static let flagMaxWidth: CGFloat = 15
        static let flagMaxHeight: CGFloat = 10
    }

    /// Number of countries listed per column before the "+n more" line takes over.
    private static let previewCountryLimit = 3

    /// Number of trips listed on the dashboard before the card only links onwards.
    private static let recentTripLimit = 3

    /// Head start given to the on-screen map preview before the interactive map's geometry
    /// is built in the background.
    private static let geometryWarmUpDelay: Duration = .milliseconds(600)

    // MARK: - Properties

    /// Shared navigation path of the first tab; ``AppRoute`` values appended here are
    /// resolved by ``RootTabView``.
    @Binding var path: NavigationPath

    @StateObject private var viewModel = MainScreenViewModel()
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Query(sort: \Country.iso2) private var allCountries: [Country]
    @Query private var allTrips: [Trip]

    // MARK: - Body

    var body: some View {

        ScrollView {

            LazyVStack(spacing: Layout.stackSpacing) {

                NavigationLink(value: AppRoute.mapScreen) {

                    FlatMapView(selectionEnabled: false,
                                labelsEnabled: false,
                                renderMode: .stretch,
                                projectionMode: .plateCarree,
                                selectedCountry: .constant(nil),
                                filter: .constant(.all))
                        .accessibilityLabel("World map")
                        .disabled(true)
                        .padding(.horizontal)
                        .aspectRatio(Layout.mapPreviewAspectRatio, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.mapPreviewCornerRadius,
                                                    style: .continuous))
                        .glassEffect(.regular.interactive(),
                                     in: .rect(cornerRadius: Layout.mapPreviewCornerRadius))
                        .padding(.top)
                }

                StatView()

                countryCard

                tripsCard
            }
            .padding(.horizontal, Layout.screenHorizontalPadding)
        }
        // The tab bar's own inset is already in the scroll view; this is the gap on top of
        // it, so the last card ends clear of the bar instead of flush against it. It is the
        // stack's own rhythm rather than a guess at the bar's height.
        .contentMargins(.bottom, Layout.stackSpacing, for: .scrollContent)
        .navigationTitle("Your Countries")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            let source = showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries
            viewModel.update(from: source)
        }
        .onChange(of: allCountries) { _, newValue in
            let source = showOnlyUNMembers ? newValue.filter { $0.isUNMember } : newValue
            viewModel.update(from: source)
        }
        .onChange(of: showOnlyUNMembers) { _, newValue in
            let source = newValue ? allCountries.filter { $0.isUNMember } : allCountries
            viewModel.update(from: source)
        }
        .task(id: allCountries.count) {
            await warmInteractiveMapGeometry()
        }
    }

    // MARK: - Geometry warm-up

    /// The preview above uses a different projection and a simplified variant than
    /// the interactive map, so opening the map used to trigger a ~500 ms build on
    /// the first tap. Building it here in the background makes that tap instant.
    ///
    /// - Note: Runs on the main actor and hands only the `Sendable` resolver index to the
    ///   cache; ``Country`` is a SwiftData model and must not cross into background work.
    private func warmInteractiveMapGeometry() async {

        guard !allCountries.isEmpty else { return }

        // Let the preview finish first, it is what the user is looking at.
        try? await Task.sleep(for: Self.geometryWarmUpDelay)
        guard !Task.isCancelled else { return }

        let resolver = CountryIndex(countries: allCountries).resolverIndex

        await FlatMapShapeCache.shared.warm(
            projectionMode: ShapeRequest.interactiveMap.projection,
            resolver: resolver,
            variant: ShapeRequest.interactiveMap.variant
        )
    }

    // MARK: - CountryCard

    /// Card summarising visited and wishlisted countries; pushes the full country list.
    private var countryCard: some View {

        NavigationLink(value: AppRoute.fullCountryList) {

            VStack(alignment: .leading, spacing: Layout.cardContentSpacing) {

                Text("Countries & Territories")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(alignment: .top, spacing: Layout.cardColumnSpacing) {
                    countryPreviewList(for: "Visited", countries: viewModel.visitedCountries)

                    countryPreviewList(for: "On Wishlist", countries: viewModel.wishlistCountries)
                }

                Divider()

                cardDetailLink(title: "See Full List")
            }
        }
        .tint(.primary)
        .padding(.vertical, Layout.cardVerticalPadding)
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Layout.cardCornerRadius))
        .contentShape(Rectangle())
    }

    /// One column of the country card: a count, a caption and the first few countries.
    ///
    /// - Parameters:
    ///   - title: Caption next to the count, looked up in the string catalog.
    ///   - countries: The countries of this column; only the first
    ///     ``MainScreen/previewCountryLimit`` are listed, the rest become a "+n more" line.
    @ViewBuilder
    private func countryPreviewList(for title: LocalizedStringKey,
                                    countries: [Country]) -> some View {

        let remainingCount = max(0, countries.count - Self.previewCountryLimit)

        VStack(alignment: .leading, spacing: Layout.previewListSpacing) {

            HStack(spacing: Layout.countLabelSpacing) {

                Text(verbatim: "\(countries.count)")
                    .font(.headline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Layout.countryRowSpacing) {

                ForEach(countries.prefix(Self.previewCountryLimit), id: \.iso2) { country in

                    HStack(spacing: Layout.flagLabelSpacing) {

                        Image(country.iso2.lowercased())
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Layout.flagCornerRadius,
                                                        style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Layout.flagCornerRadius,
                                                 style: .continuous)
                                    .stroke(.quaternary, lineWidth: Layout.flagBorderWidth)
                            )
                            .frame(maxWidth: Layout.flagMaxWidth, maxHeight: Layout.flagMaxHeight)

                        Text(country.nameEnglish)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .truncationMode(.tail)
                            .lineLimit(1)
                    }
                    .font(.footnote)
                }
                if remainingCount > 0 {
                    Text("+\(remainingCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - TripsCard

    /// Card listing the most recent trips; pushes the trips list.
    ///
    /// Shows at most ``MainScreen/recentTripLimit`` of them, so the dashboard states what has
    /// happened lately instead of only counting it.
    ///
    /// Pushes ``AppRoute/tripsList`` rather than selecting the trips tab: the dashboard is a
    /// summary, and drilling into one of its cards must stay undoable with the back gesture,
    /// exactly as the map and country cards behave.
    private var tripsCard: some View {

        NavigationLink(value: AppRoute.tripsList) {

            VStack(alignment: .leading, spacing: Layout.cardContentSpacing) {

                HStack(spacing: Layout.countLabelSpacing) {

                    Text("Trips")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(verbatim: "\(allTrips.count)")
                        .font(.headline).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                recentTripList

                Divider()

                cardDetailLink(title: "See All Trips")
            }
        }
        .tint(.primary)
        .padding(.vertical, Layout.cardVerticalPadding)
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Layout.cardCornerRadius))
        .contentShape(Rectangle())
    }

    /// The most recent trips, or a line explaining the card while there are none.
    @ViewBuilder
    private var recentTripList: some View {

        let recent = TripFormatting.sortedNewestFirst(allTrips).prefix(Self.recentTripLimit)

        if recent.isEmpty {
            Text("Group the countries of a journey into a trip.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Layout.previewListSpacing) {
                ForEach(recent) { trip in
                    HStack(spacing: Layout.flagLabelSpacing) {

                        Text(TripFormatting.displayTitle(for: trip))
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let range = TripFormatting.dateRange(for: trip) {
                            Text(range)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// Footer row of a card, hinting that the card is tappable.
    ///
    /// - Parameter title: Caption of the row, looked up in the string catalog.
    @ViewBuilder
    private func cardDetailLink(title: LocalizedStringKey) -> some View {

        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        MainScreen(path: .constant(NavigationPath()))
    }
}
