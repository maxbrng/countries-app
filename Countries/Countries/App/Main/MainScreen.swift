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
        /// Height of a flag in the country columns.
        static let flagHeight: CGFloat = 10
        /// Height of a flag in the trip rows, where several sit side by side.
        static let tripFlagHeight: CGFloat = 14
        /// How far each flag of a trip overlaps the one before it, as a share of its width.
        ///
        /// Overlapping rather than spacing them keeps a five-country trip the same width as a
        /// two-country one, so the titles beside them stay on a common left edge.
        static let tripFlagOverlapShare: CGFloat = 0.35
        /// Vertical spacing between a trip's title and its detail line.
        static let tripRowSpacing: CGFloat = 3
        /// Vertical spacing between two trip rows.
        static let tripListSpacing: CGFloat = 14
    }

    /// Number of countries listed per column before the "+n more" line takes over.
    private static let previewCountryLimit = 3

    /// Number of trips listed on the dashboard before the card only links onwards.
    private static let recentTripLimit = 3

    /// Number of flags shown per trip before the row stops adding them.
    ///
    /// Four is what fits beside a title at this width once they overlap; beyond that the count
    /// on the line underneath is the better answer than a row of slivers.
    private static let tripFlagLimit = 4

    /// Head start given to the on-screen map preview before the interactive map's geometry
    /// is built in the background.
    private static let geometryWarmUpDelay: Duration = .milliseconds(600)

    // MARK: - Properties

    /// Shared navigation path of the first tab; ``AppRoute`` values appended here are
    /// resolved by ``RootTabView``.
    @Binding var path: NavigationPath

    @StateObject private var viewModel = MainScreenViewModel()
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @Environment(\.modelContext) private var modelContext
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

                        CountryFlag(iso2: country.iso2, height: Layout.flagHeight)

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
            VStack(alignment: .leading, spacing: Layout.tripListSpacing) {
                ForEach(recent) { trip in
                    tripRow(for: trip)
                }
            }
        }
    }

    /// One trip on the dashboard: its flags, its name and what it consisted of.
    ///
    /// - Parameter trip: The trip to describe.
    @ViewBuilder
    private func tripRow(for trip: Trip) -> some View {

        HStack(spacing: Layout.flagLabelSpacing) {

            tripFlags(for: trip)

            VStack(alignment: .leading, spacing: Layout.tripRowSpacing) {

                Text(TripFormatting.displayTitle(for: trip))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(Self.tripDetailLine(for: trip))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// The flags of a trip's countries, overlapping, newest-added last.
    ///
    /// - Parameter trip: The trip whose countries to show.
    @ViewBuilder
    private func tripFlags(for trip: Trip) -> some View {

        let shown = trip.countries.prefix(Self.tripFlagLimit)
        let overlap = Layout.tripFlagHeight * CountryFlag.aspectRatio * Layout.tripFlagOverlapShare

        HStack(spacing: -overlap) {
            ForEach(Array(shown.enumerated()), id: \.element.iso2) { index, country in
                CountryFlag(iso2: country.iso2, height: Layout.tripFlagHeight)
                    // Later flags on top, so the stack reads left to right rather than
                    // looking like it was dealt backwards.
                    .zIndex(Double(-index))
            }
        }
        .accessibilityHidden(true)
    }

    /// The second line of a trip row: when it was, and how much of it there was.
    ///
    /// - Parameter trip: The trip to describe.
    /// - Returns: The parts that apply, joined by a middle dot. Never empty: a trip with no
    ///   dates and no countries still says that it has none.
    private static func tripDetailLine(for trip: Trip) -> String {

        var parts: [String] = []

        if let range = TripFormatting.dateRange(for: trip) {
            parts.append(range)
        }

        let count = trip.countries.count
        parts.append(count == 1
                     ? String(localized: "1 country")
                     : String(localized: "\(count) countries"))

        return parts.joined(separator: " · ")
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
