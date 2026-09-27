//
//  SettingsScreen.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "Settings")

/// App settings, pushed from the main screen's toolbar.
///
/// - Note: The stored flags are read straight from `@AppStorage` by the screens that need
///   them, so this screen holds no view model of its own.
struct SettingsScreen: View {

    // MARK: - Properties

    /// Restricts the country list, the statistics and the map preview to UN member states.
    /// Defaults to `false`.
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false

    /// Which renderer the map screen opens in. Shares its key with ``MapScreenModel``.
    @AppStorage(MapAppearance.storageKey) private var mapAppearance: MapAppearance = .twoD

    @Environment(\.modelContext) private var modelContext

    /// Counts shown in the reset warning, recomputed each time the first step is opened.
    @State private var resetSummary: DataResetService.Summary?

    /// Second step of the reset, shown only after the warning was acknowledged.
    @State private var showsFinalResetConfirmation = false

    // MARK: - Body

    var body: some View {
        List {
            mapSection
            generalSection
            privacySection
            aboutSection
            resetSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var mapSection: some View {
        Section("Map") {
            Picker("Map style", selection: $mapAppearance) {
                ForEach(MapAppearance.allCases, id: \.self) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Only show UN countries", isOn: $showOnlyUNMembers)
        }
    }

    /// Facts about what the app stores and sends, not a statement of intent.
    private var privacySection: some View {
        Section("Privacy") {
            fact("Your countries, trips and settings are stored on this device only.")
            fact("The app has no account and no server of its own. Nothing you enter leaves the device.")
            fact("iCloud sync is switched off, so nothing is copied to your other devices.")
            fact("Country outlines and country data are built into the app.")
            fact("The 3D globe is Apple Maps and loads map imagery from Apple while it is open. The flat map loads nothing.")
            fact("There is no analytics, no tracking and no advertising.")
        }
    }

    /// Attribution and the running version.
    private var aboutSection: some View {
        Section("About") {

            LabeledContent("Version") {
                Text(verbatim: Self.versionDescription)
            }

            VStack(alignment: .leading, spacing: Layout.factSpacing) {
                Text("Map data")
                    .font(.subheadline)
                Text(verbatim: "Natural Earth — naturalearthdata.com (public domain)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset all data", role: .destructive) {
                prepareReset()
            }
        } footer: {
            Text("Removes everything you marked or recorded and starts over.")
        }
        .alert("Reset all data?", isPresented: resetWarningBinding, presenting: resetSummary) { _ in
            Button("Cancel", role: .cancel) { resetSummary = nil }
            Button("Continue", role: .destructive) {
                resetSummary = nil
                showsFinalResetConfirmation = true
            }
        } message: { summary in
            Text(Self.warningText(for: summary))
        }
        .alert("This cannot be undone", isPresented: $showsFinalResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { performReset() }
        } message: {
            Text("The app will start as it did on the first launch.")
        }
    }

    // MARK: - Layout

    /// Spacings used by the fact and attribution rows.
    private enum Layout {
        /// Vertical gap between a label and its detail line.
        static let factSpacing: CGFloat = 4
    }

    // MARK: - Content helpers

    /// One line of the privacy section.
    ///
    /// - Parameter text: The statement, looked up in the string catalog.
    private func fact(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Marketing version and build number, for example `1.0 (42)`.
    private static var versionDescription: String {

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"

        return "\(version) (\(build))"
    }

    /// Spells out what the reset removes, so the warning names real numbers.
    ///
    /// Empty categories are left out, and each line picks its own singular or plural key.
    ///
    /// - Note: Two forms are enough for the shipped languages, English and German. A language
    ///   with more plural categories would need the catalog's plural variations instead.
    ///
    /// - Parameter summary: The counts read from the store.
    /// - Returns: One line per non-empty category, or a note that nothing is stored.
    private static func warningText(for summary: DataResetService.Summary) -> String {

        guard !summary.isEmpty else {
            return String(localized: "There is nothing stored yet, so nothing will be lost.")
        }

        var lines: [String] = []

        if summary.visitedCount > 0 {
            lines.append(summary.visitedCount == 1
                         ? String(localized: "1 visited country")
                         : String(localized: "\(summary.visitedCount) visited countries"))
        }
        if summary.wishlistCount > 0 {
            lines.append(summary.wishlistCount == 1
                         ? String(localized: "1 wishlisted country")
                         : String(localized: "\(summary.wishlistCount) wishlisted countries"))
        }
        if summary.tripCount > 0 {
            lines.append(summary.tripCount == 1
                         ? String(localized: "1 trip")
                         : String(localized: "\(summary.tripCount) trips"))
        }

        return lines.joined(separator: "\n")
    }

    /// Drives the first alert off ``resetSummary`` so the counts and the alert appear together.
    private var resetWarningBinding: Binding<Bool> {
        Binding(
            get: { resetSummary != nil },
            set: { if !$0 { resetSummary = nil } }
        )
    }

    // MARK: - Actions

    /// Reads what a reset would remove and opens the first of the two confirmations.
    private func prepareReset() {
        do {
            resetSummary = try DataResetService.summary(in: modelContext)
        } catch {
            logger.error("Could not read the reset summary: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Runs the reset after both confirmations.
    private func performReset() {
        do {
            try DataResetService.resetEverything(in: modelContext)
        } catch {
            logger.error("Reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
