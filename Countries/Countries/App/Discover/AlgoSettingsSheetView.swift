//
//  AlgoSettingsSheetView.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//

import SwiftUI
import SwiftData

struct AlgoSettingsSheetView: View {

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage("selectedMockUser") private var selectedMockUser: Int = 0

    // MARK: - SwiftData
    @Query private var allPreferences: [UserPreferences]

    // MARK: - Draft State (editable copy)
    @State private var prefs: UserPreferences?
    @State private var original: PreferencesDraft?
    @State private var draft: PreferencesDraft = .empty

    @State private var showDiscardAlert = false

    // MARK: - Dirty state
    private var hasUnsavedChanges: Bool {
        guard let original else { return false }
        return draft != original
    }

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
                    if prefs != nil && hasUnsavedChanges {
                        Button("Cancel") { cancelTapped() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if prefs != nil && hasUnsavedChanges {
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
            .task(id: selectedMockUser) {
                loadOrCreatePreferencesAndPrepareDraft()
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-update preferences")
                    Text("When enabled, preferences adapt based on visited countries and trips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Profile") {
                Text("Mock User \(selectedMockUser + 1)")
                    .foregroundStyle(.secondary)
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
                ForEach(CostLevel.allCases, id: \.self) { lvl in
                    Text("\(lvl.rawValue)").tag(Optional(lvl))
                }
            }

            Picker("Minimum Safety", selection: $draft.minSafety) {
                Text("No filter").tag(SafetyLevel?.none)
                ForEach(SafetyLevel.allCases, id: \.self) { lvl in
                    Text("\(lvl.rawValue)").tag(Optional(lvl))
                }
            }
        }
    }

    private var seasonAndDurationSection: some View {
        Section("Trip Context") {

            Picker("Preferred Duration", selection: $draft.preferredDuration) {
                Text("No preference").tag(TravelDuration?.none)
                ForEach(TravelDuration.allCases, id: \.self) { d in
                    Text(durationLabel(d)).tag(Optional(d))
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

    private func bindingForTravelTag(_ tag: TravelTag) -> Binding<Bool> {
        Binding(
            get: { draft.desiredTags.contains(tag) },
            set: { isOn in
                if isOn { draft.desiredTags.insert(tag) }
                else { draft.desiredTags.remove(tag) }
            }
        )
    }

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

    private func cancelTapped() {
        if hasUnsavedChanges {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private func doneTapped() {
        guard let prefs else { return }
        applyDraftToModel(draft, prefs: prefs)
        do {
            try context.save()
        
            original = PreferencesDraft(from: prefs)
            draft = original ?? .empty
            
            dismiss()
        } catch {
            // optional: you could show another alert here
            print("Save failed:", error)
        }
    }

    private func discardAndClose() {
        // reset draft back to original
        if let original {
            draft = original
        }
        dismiss()
    }

    // MARK: - Loading

    private func loadOrCreatePreferencesAndPrepareDraft() {
        // Find existing record for selectedMockUser
        print("selectedMockUser", selectedMockUser)
        if let existing = allPreferences.first(where: { $0.profileKey == selectedMockUser }) {
            prefs = existing
            let snap = PreferencesDraft(from: existing)
            original = snap
            draft = snap
            return
        }

        print("Error loadOrCreatePreferencesAndPrepareDraft")
        do {
            let prefs = try context.fetch(FetchDescriptor<UserPreferences>())
            print("Prefs count:", prefs.count)
            for p in prefs {
                print("profileKey:", p.profileKey, "tags:", p.desiredTags)
            }
        } catch {
            print("Failed to fetch UserPreferences:", error)
        }

    }

    // MARK: - Helpers

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

    private func durationLabel(_ d: TravelDuration) -> String {
        switch d {
        case .weekend: return "Weekend (1–3 days)"
        case .short: return "Short (4–7 days)"
        case .medium: return "Medium (8–14 days)"
        case .long: return "Long (15–30 days)"
        case .nomad: return "Nomad (30+ days)"
        }
    }
}

// MARK: - Draft Model

private struct PreferencesDraft: Equatable {
    var autoUpdateEnabled: Bool

    var desiredTags: Set<TravelTag>
    var preferredClimate: Set<ClimateTag>
    
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

    var maxCostLevel: CostLevel?
    var minSafety: SafetyLevel?

    var preferredDuration: TravelDuration?
    var preferredSeason: Season?

    var recommendationMode: RecommendationMode

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


