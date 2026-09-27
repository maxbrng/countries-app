//
//  CountryDetailsView.swift
//  Countries
//
//  Created by Max Breuning on 04.01.26.
//

import SwiftUI
import SwiftData

/// Detail screen for a single ``Country``: a flag header, a read-only list of the stored
/// attributes, the free-form notes and a bottom bar for toggling visited / wishlist status.
///
/// - Note: This screen is always pushed onto a navigation stack, so it hides the tab bar
///   for as long as it is on screen.
struct CountryDetailsView: View {

    // MARK: - Layout

    /// Sizes, radii and opacities used by this screen.
    private enum Layout {
        /// Vertical spacing between header, info block and notes block.
        static let sectionSpacing: CGFloat = 16
        /// Horizontal spacing between the flag and the title column of the header.
        static let headerSpacing: CGFloat = 16
        /// Vertical spacing inside the header's title column.
        static let headerTextSpacing: CGFloat = 6
        /// Horizontal spacing between the status badge and the "UN Member" label.
        static let badgeRowSpacing: CGFloat = 8
        /// Vertical spacing between two info rows.
        static let infoRowSpacing: CGFloat = 12
        /// Vertical spacing inside the notes block.
        static let notesSpacing: CGFloat = 8
        static let flagCornerRadius: CGFloat = 8
        static let flagBorderWidth: CGFloat = 1
        static let flagMaxWidth: CGFloat = 80
        static let flagMaxHeight: CGFloat = 56
        /// Fixed width of the label column so every value column starts at the same offset.
        static let infoTitleWidth: CGFloat = 110
        static let badgeHorizontalPadding: CGFloat = 8
        static let badgeVerticalPadding: CGFloat = 4
        /// Opacity of the tinted capsule behind a status badge.
        static let badgeBackgroundOpacity: Double = 0.2
        /// Opacity of the tinted capsule behind the "UN Member" label.
        static let unMemberBackgroundOpacity: Double = 0.15
    }

    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext

    /// The country whose stored attributes this screen renders.
    let country: Country

    @State private var showingNotesEditor = false

    // MARK: - Body

    var body: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {

                header

                Divider()

                infoSection

                Divider()
                notesSection(text: country.notes ?? "")
            }
            .padding()
        }
        .navigationTitle(country.nameEnglish)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Header

    private var header: some View {

        HStack(alignment: .center, spacing: Layout.headerSpacing) {

            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.flagCornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: Layout.flagBorderWidth)
                )
                .frame(maxWidth: Layout.flagMaxWidth, maxHeight: Layout.flagMaxHeight)

            VStack(alignment: .leading, spacing: Layout.headerTextSpacing) {
                Text(country.nameEnglish)
                    .font(.title2).fontWeight(.semibold)
                if let native = country.nativeName, !native.isEmpty {
                    Text(native)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: Layout.badgeRowSpacing) {
                    badge(for: country.status)
                    if country.isUNMember {
                        Label("UN Member", systemImage: "globe")
                            .font(.caption)
                            .padding(.horizontal, Layout.badgeHorizontalPadding)
                            .padding(.vertical, Layout.badgeVerticalPadding)
                            .background(.blue.opacity(Layout.unMemberBackgroundOpacity))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Info

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Layout.infoRowSpacing) {

            if let nativeName = country.nativeName {
                infoRow(title: "Native Name", value: nativeName)
            }

            if let continent = country.continent {
                infoRow(title: "Continent", value: continent)
            }

            if let capital = country.capital, !capital.isEmpty {
                infoRow(title: "Capital", value: capital)
            }

            // Status
            infoRow(title: "Status", value: statusValue(for: country.status))

            // UN Member and Source Translations
            infoRow(title: "UN Member", value: country.isUNMember ? "Yes" : "No")
            infoRow(title: "Has Source Translations",
                    value: country.dataHadSourceTranslations ? "Yes" : "No")

            // Phone Codes
            if !country.phoneCodes.isEmpty {
                let codes = country.phoneCodes.map { "+\($0)" }.joined(separator: ", ")
                infoRow(title: "Phone Codes", value: codes)
            }

            // Currencies & Languages
            if !country.currencies.isEmpty {
                infoRow(title: "Currencies", value: country.currencies.joined(separator: ", "))
            }

            if !country.languages.isEmpty {
                infoRow(title: "Languages", value: country.languages.joined(separator: ", "))
            }

            // ISO Codes
            if let iso3 = country.iso3, !iso3.isEmpty {
                infoRow(title: "ISO3", value: iso3)
            }
            infoRow(title: "ISO2", value: country.iso2)

            // Tags
            if !country.travelTags.isEmpty {
                let tags = country.travelTags.map { $0.rawValue.capitalized }.joined(separator: ", ")
                infoRow(title: "Travel Tags", value: tags)
            }

            if !country.climateTags.isEmpty {
                let tags = country.climateTags.map { $0.rawValue.capitalized }.joined(separator: ", ")
                infoRow(title: "Climate Tags", value: tags)
            }

            // Levels
            infoRow(title: "Cost Level", value: String(describing: country.costLevel).capitalized)
            infoRow(title: "Safety Level", value: String(describing: country.safetyLevel).capitalized)

            // Hero Image URL
            if let hero = country.heroImageURL, !hero.isEmpty {
                infoRow(title: "Hero Image URL", value: hero)
            }

            // Trips count
            infoRow(title: "Trips", value: "\(country.trips.count)")
        }
    }

    // MARK: - Notes

    private func notesSection(text: String) -> some View {

        VStack(alignment: .leading, spacing: Layout.notesSpacing) {

            HStack {

                Text("Notes")
                    .font(.headline)

                Spacer()

                Button("Edit") { showingNotesEditor = true }
            }

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(country: country)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {

        ToolbarItemGroup(placement: .bottomBar) {

            Button {
                toggleStatus(.visited)
            } label: {
                Label(country.status == .visited ? "Visited" : "Mark Visited",
                      systemImage: country.status == .visited ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .tint(.green)

            Button {
                toggleStatus(.wishlist)
            } label: {
                Label(country.status == .wishlist ? "On Wishlist" : "Add to Wishlist",
                      systemImage: country.status == .wishlist ? "star.fill" : "star")
            }
            .tint(.blue)
        }
    }

    // MARK: - Actions

    /// Applies `newStatus` to the country and lets ``PreferencesService`` re-derive the
    /// recommendation preferences.
    ///
    /// - Parameter newStatus: The status the tapped toolbar button stands for. Tapping the
    ///   button of the status the country already has clears it again.
    private func toggleStatus(_ newStatus: CountryStatus) {
        try? PreferencesService.toggleStatus(newStatus, for: country, in: modelContext)
    }

    // MARK: - Helpers

    /// One label / value line of the info block.
    ///
    /// - Parameters:
    ///   - title: The label, looked up in the string catalog.
    ///   - value: The already formatted value. Stored data such as a native name or an ISO
    ///     code, so it is rendered verbatim and never looked up.
    /// - Returns: A baseline-aligned row with a fixed-width label column.
    private func infoRow(title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: Layout.infoTitleWidth, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    /// Value shown in the "Status" info row for `status`.
    private func statusValue(for status: CountryStatus) -> String {
        switch status {
        case .none: return "None"
        case .visited: return "Visited"
        case .wishlist: return "Wishlist"
        }
    }

    /// Capsule badge for a country that is visited or wishlisted.
    ///
    /// - Parameter status: The country's status; ``CountryStatus/none`` renders nothing.
    @ViewBuilder
    private func badge(for status: CountryStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .visited:
            Text("Visited")
                .font(.caption)
                .padding(.vertical, Layout.badgeVerticalPadding)
                .padding(.horizontal, Layout.badgeHorizontalPadding)
                .background(.green.opacity(Layout.badgeBackgroundOpacity))
                .clipShape(Capsule())
        case .wishlist:
            Text("Wishlist")
                .font(.caption)
                .padding(.vertical, Layout.badgeVerticalPadding)
                .padding(.horizontal, Layout.badgeHorizontalPadding)
                .background(.blue.opacity(Layout.badgeBackgroundOpacity))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Notes editor

/// Modal editor for a country's notes. Trims the text and saves on confirmation.
private struct NotesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text: String
    let country: Country

    init(country: Country) {
        self.country = country
        _text = State(initialValue: country.notes ?? "")
    }

    var body: some View {

        NavigationStack {

            TextEditor(text: $text)
                .padding()
                .navigationTitle("Edit Notes")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            country.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    NavigationStack {
        CountryDetailsView(country: Country(
            iso2: "DE",
            iso3: "DEU",
            nameEnglish: "Germany",
            nativeName: "Deutschland",
            continent: "EU",
            capital: "Berlin",
            phoneCodes: [49],
            currencies: ["EUR"],
            languages: ["German"],
            status: .visited,
            isUNMember: true,
            dataHasSourceTranslation: true,
            notes: "Road trip along the Rhine, revisit in autumn.",
            travelTags: [.culture, .citytrip, .food],
            climateTags: [.mild],
            costLevel: .expensive,
            safetyLevel: .verySafe,
            heroImageURL: "https://example.com/berlin.jpg",
            translations: ["de": "Deutschland", "en": "Germany"]
        ))
    }
}
