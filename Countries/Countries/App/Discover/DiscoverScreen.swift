//
//  DiscoverScreen.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import SwiftData

/// Browse countries the user has not visited yet, narrowed by travel tags, climate and
/// continent.
///
/// - Note: Deliberately does no ranking. Countries are listed alphabetically, and every result
///   is there because it matches what the user picked, not because a score put it there.
struct DiscoverScreen: View {

    // MARK: - Layout

    /// Spacings of the filter bar and geometry of the paging card stack.
    ///
    /// `nonisolated` because the `visualEffect` closure is `@Sendable`; these are immutable
    /// value constants, so reading them off the main actor is safe.
    private nonisolated enum Layout {

        /// Horizontal spacing between two filter chips.
        static let chipSpacing: CGFloat = 8
        /// Inset of the chip row, matching the list's own margins.
        static let chipRowHorizontalPadding: CGFloat = 16
        static let chipVerticalPadding: CGFloat = 6
        static let chipHorizontalPadding: CGFloat = 12

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

    // MARK: - Presentation

    /// How the results are shown.
    ///
    /// Persisted, so the choice survives leaving the tab.
    enum Presentation: String, CaseIterable {

        /// One country per screen, paged vertically.
        case cards

        /// A compact scrolling list.
        case list

        /// Symbol of the button that switches to the *other* presentation.
        var toggleSymbolName: String {
            switch self {
            case .cards: "list.bullet"
            case .list: "rectangle.stack"
            }
        }

        /// Accessibility label of that button.
        var toggleLabel: LocalizedStringKey {
            switch self {
            case .cards: "Show as list"
            case .list: "Show as cards"
            }
        }

        /// The presentation the toggle switches to.
        var toggled: Presentation {
            self == .cards ? .list : .cards
        }
    }

    // MARK: - Properties

    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    @AppStorage("discoverPresentation") private var presentation: Presentation = .cards

    @Query(sort: \Country.nameEnglish) private var allCountries: [Country]

    /// What the user has narrowed the list down to.
    @State private var filter = DiscoverFilter()

    // MARK: - Body

    var body: some View {

        let base = showOnlyUNMembers ? allCountries.filter(\.isUNMember) : allCountries
        let results = filter.apply(to: base)

        Group {
            if results.isEmpty {
                emptyState
            } else if presentation == .cards {
                cardStack(for: results)
            } else {
                resultList(for: results)
            }
        }
        .safeAreaInset(edge: .top) { filterBar }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Country.self) { country in
            CountryDetailsView(country: country)
        }
        .toolbar {
            if !filter.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { filter = DiscoverFilter() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { presentation = presentation.toggled }
                } label: {
                    Label(presentation.toggleLabel, systemImage: presentation.toggleSymbolName)
                }
            }
        }
    }

    // MARK: - Card stack

    /// One country per screen, paged vertically.
    ///
    /// The card scales and fades towards the viewport edge, so the card being read is
    /// unmistakably the one in the middle.
    ///
    /// - Parameter countries: The countries to page through, already filtered and sorted.
    private func cardStack(for countries: [Country]) -> some View {

        GeometryReader { geo in

            let cardHeight = geo.size.height - Layout.cardInset
            let cardWidth = geo.size.width - Layout.cardInset

            ScrollView(.vertical) {

                LazyVStack(spacing: 0) {

                    ForEach(countries, id: \.iso2) { country in

                        NavigationLink(value: country) {

                            CountryCardView(country: country,
                                            height: cardHeight,
                                            width: cardWidth)
                                .glassEffect(
                                    .regular.interactive(),
                                    in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius,
                                                         style: .continuous)
                                )
                                .frame(width: cardWidth, height: cardHeight)
                                .containerRelativeFrame(.vertical, count: 1, spacing: 0)
                                .visualEffect { content, proxy in
                                    // 0 for the centred card, 1 at the viewport edge.
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
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Layout.stackHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
        }
    }

    // MARK: - List

    /// The compact alternative to the card stack.
    ///
    /// - Parameter countries: The countries to list, already filtered and sorted.
    private func resultList(for countries: [Country]) -> some View {

        List {
            Section {
                ForEach(countries, id: \.iso2) { country in
                    DiscoverCountryRow(country: country)
                }
            } header: {
                Text("\(countries.count) countries")
            }
        }
    }

    // MARK: - Filter bar

    /// Horizontally scrolling travel-tag chips, plus the climate and continent menus.
    private var filterBar: some View {

        ScrollView(.horizontal) {
            HStack(spacing: Layout.chipSpacing) {

                climateMenu
                continentMenu

                Divider()
                    .frame(height: Layout.chipHorizontalPadding * 2)

                ForEach(TravelTag.allCases, id: \.self) { tag in
                    chip(title: tag.title,
                         symbolName: tag.symbolName,
                         isOn: filter.travelTags.contains(tag)) {
                        toggle(tag)
                    }
                }
            }
            .padding(.horizontal, Layout.chipRowHorizontalPadding)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, Layout.chipVerticalPadding)
        .background(.bar)
    }

    /// Picks one climate, or clears the choice.
    private var climateMenu: some View {
        Menu {
            Button("Any climate") { filter.climate = nil }
            ForEach(ClimateTag.allCases, id: \.self) { climate in
                Button { filter.climate = climate } label: {
                    if filter.climate == climate {
                        Label(climate.title, systemImage: "checkmark")
                    } else {
                        Text(climate.title)
                    }
                }
            }
        } label: {
            menuChip(title: filter.climate?.title ?? "Climate", isOn: filter.climate != nil)
        }
    }

    /// Picks one continent, or clears the choice.
    private var continentMenu: some View {

        let continents = Set(allCountries.compactMap(\.continent)).sorted()

        return Menu {
            Button("All continents") { filter.continent = nil }
            ForEach(continents, id: \.self) { continent in
                Button { filter.continent = continent } label: {
                    if filter.continent == continent {
                        Label(continent, systemImage: "checkmark")
                    } else {
                        Text(continent)
                    }
                }
            }
        } label: {
            menuChip(title: filter.continent.map { LocalizedStringKey($0) } ?? "Continent",
                     isOn: filter.continent != nil)
        }
    }

    // MARK: - Chips

    /// A tappable filter chip.
    ///
    /// - Parameters:
    ///   - title: Label of the chip, looked up in the string catalog.
    ///   - symbolName: SF Symbol shown before the label.
    ///   - isOn: Whether the chip is currently selected.
    ///   - action: Run when the chip is tapped.
    private func chip(title: LocalizedStringKey,
                      symbolName: String,
                      isOn: Bool,
                      action: @escaping () -> Void) -> some View {

        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline)
                .padding(.vertical, Layout.chipVerticalPadding)
                .padding(.horizontal, Layout.chipHorizontalPadding)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
    }

    /// The non-tappable label of a menu, styled like ``chip(title:symbolName:isOn:action:)``.
    ///
    /// - Parameters:
    ///   - title: Current selection, or the menu's name while nothing is selected.
    ///   - isOn: Whether something is selected.
    private func menuChip(title: LocalizedStringKey, isOn: Bool) -> some View {
        Label(title, systemImage: "chevron.down")
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .padding(.vertical, Layout.chipVerticalPadding)
            .padding(.horizontal, Layout.chipHorizontalPadding)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
    }

    // MARK: - Empty state

    /// Shown when the filter matches nothing.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No country carries all of this. Try fewer filters.")
        } actions: {
            Button("Reset filters") { filter = DiscoverFilter() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    /// Adds `tag` to the filter, or removes it when it is already in.
    ///
    /// - Parameter tag: The tapped travel tag.
    private func toggle(_ tag: TravelTag) {

        if filter.travelTags.contains(tag) {
            filter.travelTags.remove(tag)
            return
        }
        filter.travelTags.insert(tag)
    }
}

#Preview {
    NavigationStack {
        DiscoverScreen()
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
