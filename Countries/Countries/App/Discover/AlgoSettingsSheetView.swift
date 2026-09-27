//
//  AlgoSettingsSheetView.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries",
                            category: "AlgoSettings")

/// Sheet that lets the user edit the recommendation preferences by hand.
///
/// Edits are collected in a ``PreferencesDraft`` and only written back to ``UserPreferences`` when
/// the user confirms, so a cancelled sheet leaves the store untouched. Saving sets
/// ``UserPreferences/userDidCustomize``, which stops ``PreferencesService`` from re-deriving the
/// preferences from the travel history; the "Auto-update preferences" toggle is the inverse of that
/// flag.
struct AlgoSettingsSheetView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // MARK: - Draft State (editable copy)

    @State private var prefs: UserPreferences?
    @State private var original: PreferencesDraft?
    @State private var draft: PreferencesDraft = .empty

    @State private var showDiscardAlert = false

    // MARK: - Constants

    /// Spacing inside the toggle label stack.
    private static let toggleLabelSpacing: CGFloat = 4

    // MARK: - Dirty state

    private var hasUnsavedChanges: Bool {
        guard let original else { return false }
        return draft != original
    }

    /// True while a record is loaded and the draft differs from it, which is when the sheet offers
    /// the save and cancel actions instead of a plain close button.
    private var canCommitChanges: Bool {
        prefs != nil && hasUnsavedChanges
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if prefs != nil {
                    adaptiveSection
                    recommendationModeSection
                    travelTagsSection
                    climateSection
                    budgetAndSafetySection
                    seasonAndDurationSection
                } else {
                    ContentUnavailableView("Loading preferences…", systemImage: "gearshape")
                }
            }
            .navigationTitle("Algorithm Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if canCommitChanges {
                        Button("Cancel") { cancelTapped() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if canCommitChanges {
                        Button {
                            doneTapped()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button {
                            cancelTapped()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                        }
                    }
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard", role: .destructive) {
                    discardAndClose()
                }
            } message: {
                Text("You have unsaved changes. Do you want to discard them?")
            }
            .task {
                loadPreferencesAndPrepareDraft()
            }
        }
    }

    // MARK: - Sections

    private var adaptiveSection: some View {
        Section("Adaptive Behavior") {

            Toggle(isOn: Binding(
                get: { draft.autoUpdateEnabled },
                set: { draft.autoUpdateEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: Self.toggleLabelSpacing) {
                    Text("Auto-update preferences")
                    Text("When enabled, preferences adapt based on visited countries and trips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let prefs {
                LabeledContent("Last saved") {
                    Text(prefs.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recommendationModeSection: some View {
        Section("Recommendation Mode") {
            Picker("Mode", selection: $draft.recommendationMode) {
                Text("Balanced").tag(RecommendationMode.balanced)
                Text("Similar to recent").tag(RecommendationMode.similarToRecent)
                Text("Explore new").tag(RecommendationMode.exploreNew)
            }
            .pickerStyle(.segmented)
        }
    }

    private var travelTagsSection: some View {
        Section("Travel Style") {
            ForEach(TravelTag.allCases, id: \.self) { tag in
                Toggle(tag.rawValue.capitalized, isOn: bindingForTravelTag(tag))
            }
        }
    }

    private var climateSection: some View {
        Section("Climate Preference") {
            ForEach(ClimateTag.allCases, id: \.self) { tag in
                Toggle(tag.rawValue.capitalized, isOn: bindingForClimateTag(tag))
            }
        }
    }

    private var budgetAndSafetySection: some View {
        Section("Budget & Safety") {

            Picker("Max Cost Level", selection: $draft.maxCostLevel) {
                Text("No limit").tag(CostLevel?.none)
                ForEach(CostLevel.allCases, id: \.self) { level in
                    Text(verbatim: "\(level.rawValue)").tag(Optional(level))
                }
            }

            Picker("Minimum Safety", selection: $draft.minSafety) {
                Text("No filter").tag(SafetyLevel?.none)
                ForEach(SafetyLevel.allCases, id: \.self) { level in
                    Text(verbatim: "\(level.rawValue)").tag(Optional(level))
                }
            }
        }
    }

    private var seasonAndDurationSection: some View {
        Section("Trip Context") {

            Picker("Preferred Duration", selection: $draft.preferredDuration) {
                Text("No preference").tag(TravelDuration?.none)
                ForEach(TravelDuration.allCases, id: \.self) { duration in
                    Text(durationLabel(duration)).tag(Optional(duration))
                }
            }

            Picker("Preferred Season", selection: $draft.preferredSeason) {
                Text("No preference").tag(Season?.none)
                Text("Spring").tag(Optional(Season.spring))
                Text("Summer").tag(Optional(Season.summer))
                Text("Autumn").tag(Optional(Season.autumn))
                Text("Winter").tag(Optional(Season.winter))
            }
        }
    }

    // MARK: - Toggle bindings (Set-backed, reliable)

    /// Binding that adds or removes `tag` in the draft's desired travel tags.
    ///
    /// - Parameter tag: The tag the toggle stands for.
    /// - Returns: A binding that reads and writes membership in the draft.
    private func bindingForTravelTag(_ tag: TravelTag) -> Binding<Bool> {
        Binding(
            get: { draft.desiredTags.contains(tag) },
            set: { isOn in
                if isOn { draft.desiredTags.insert(tag) }
                else { draft.desiredTags.remove(tag) }
            }
        )
    }

    /// Binding that adds or removes `tag` in the draft's preferred climates.
    ///
    /// - Parameter tag: The tag the toggle stands for.
    /// - Returns: A binding that reads and writes membership in the draft.
    private func bindingForClimateTag(_ tag: ClimateTag) -> Binding<Bool> {
        Binding(
            get: { draft.preferredClimate.contains(tag) },
            set: { isOn in
                if isOn { draft.preferredClimate.insert(tag) }
                else { draft.preferredClimate.remove(tag) }
            }
        )
    }

    // MARK: - Actions

    /// Closes the sheet, asking first when the draft carries unsaved edits.
    private func cancelTapped() {
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        showDiscardAlert = true
    }

    /// Writes the draft into the model, saves and closes the sheet.
    ///
    /// On a failed save the sheet stays open with the draft intact, so the edits are not lost.
    private func doneTapped() {
        guard let prefs else { return }
        applyDraftToModel(draft, prefs: prefs)
        do {
            try context.save()

            original = PreferencesDraft(from: prefs)
            draft = original ?? .empty

            dismiss()
        } catch {
            logger.error("Failed to save preferences: \((error as NSError).localizedDescription, privacy: .public)")
        }
    }

    /// Restores the draft from the loaded snapshot and closes the sheet.
    private func discardAndClose() {
        // reset draft back to original
        if let original {
            draft = original
        }
        dismiss()
    }

    // MARK: - Loading

    /// Loads the preferences record and seeds both the draft and the snapshot it is compared against.
    private func loadPreferencesAndPrepareDraft() {
        do {
            let preferences = try PreferencesService.loadOrCreate(in: context)
            let snapshot = PreferencesDraft(from: preferences)

            prefs = preferences
            original = snapshot
            draft = snapshot
        } catch {
            logger.error("Failed to load preferences: \((error as NSError).localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    /// Copies the draft into the model record.
    ///
    /// Tag sets are stored sorted by raw value so the persisted order stays stable across saves.
    /// The toggle is inverted on purpose: auto-update on means the user did not customise.
    ///
    /// - Parameters:
    ///   - draft: The edited values.
    ///   - prefs: The record to write into.
    private func applyDraftToModel(_ draft: PreferencesDraft, prefs: UserPreferences) {
        prefs.userDidCustomize = !draft.autoUpdateEnabled
        prefs.desiredTags = Array(draft.desiredTags).sorted(by: { $0.rawValue < $1.rawValue })
        prefs.preferredClimate = Array(draft.preferredClimate).sorted(by: { $0.rawValue < $1.rawValue })
        prefs.maxCostLevel = draft.maxCostLevel
        prefs.minSafety = draft.minSafety
        prefs.preferredDuration = draft.preferredDuration
        prefs.preferredSeason = draft.preferredSeason
        prefs.recommendationMode = draft.recommendationMode
        prefs.updatedAt = .now
    }

    /// The picker label for a trip duration, including the day range the case stands for.
    ///
    /// - Parameter duration: The duration to describe.
    /// - Returns: The label shown in the duration picker.
    private func durationLabel(_ duration: TravelDuration) -> String {
        switch duration {
        case .weekend: return "Weekend (1–3 days)"
        case .short: return "Short (4–7 days)"
        case .medium: return "Medium (8–14 days)"
        case .long: return "Long (15–30 days)"
        case .nomad: return "Nomad (30+ days)"
        }
    }
}

// MARK: - Draft Model

/// Editable copy of the preference values the sheet offers.
///
/// Tags are held as sets so the toggles can insert and remove without caring about order, and the
/// type is `Equatable` so the sheet can tell an edited draft from the loaded snapshot.
private struct PreferencesDraft: Equatable {

    /// Inverse of ``UserPreferences/userDidCustomize``: while `true`, the preferences keep adapting
    /// to the travel history.
    var autoUpdateEnabled: Bool

    var desiredTags: Set<TravelTag>
    var preferredClimate: Set<ClimateTag>

    var maxCostLevel: CostLevel?
    var minSafety: SafetyLevel?

    var preferredDuration: TravelDuration?
    var preferredSeason: Season?

    var recommendationMode: RecommendationMode

    /// The draft used before a record has been loaded: no filters, no tags, balanced mode.
    static var empty: PreferencesDraft {
        PreferencesDraft(
            autoUpdateEnabled: true,
            desiredTags: [],
            preferredClimate: [],
            maxCostLevel: nil,
            minSafety: nil,
            preferredDuration: nil,
            preferredSeason: nil,
            recommendationMode: .balanced
        )
    }

    init(
        autoUpdateEnabled: Bool,
        desiredTags: Set<TravelTag>,
        preferredClimate: Set<ClimateTag>,
        maxCostLevel: CostLevel?,
        minSafety: SafetyLevel?,
        preferredDuration: TravelDuration?,
        preferredSeason: Season?,
        recommendationMode: RecommendationMode
    ) {
        self.autoUpdateEnabled = autoUpdateEnabled
        self.desiredTags = desiredTags
        self.preferredClimate = preferredClimate
        self.maxCostLevel = maxCostLevel
        self.minSafety = minSafety
        self.preferredDuration = preferredDuration
        self.preferredSeason = preferredSeason
        self.recommendationMode = recommendationMode
    }

    /// Snapshots the stored record.
    ///
    /// - Parameter prefs: The record to copy.
    init(from prefs: UserPreferences) {
        self.autoUpdateEnabled = (prefs.userDidCustomize == false)
        self.desiredTags = Set(prefs.desiredTags)
        self.preferredClimate = Set(prefs.preferredClimate)
        self.maxCostLevel = prefs.maxCostLevel
        self.minSafety = prefs.minSafety
        self.preferredDuration = prefs.preferredDuration
        self.preferredSeason = prefs.preferredSeason
        self.recommendationMode = prefs.recommendationMode
    }
}
