//
//  TripEditorView.swift
//  Countries
//
//  Created by Max Breuning on 27.09.26.
//

import SwiftUI
import SwiftData

/// Creates a new trip or edits an existing one, presented as a sheet from ``TripsListView``.
///
/// All edits are collected in a ``TripDraft`` and only written to the store on save, so a new
/// trip that is cancelled never reaches SwiftData.
struct TripEditorView: View {

    // MARK: - Properties

    /// What this editor was opened for.
    let subject: TripEditorSubject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Country.nameEnglish) private var allCountries: [Country]

    /// The state being edited.
    @State private var draft: TripDraft

    /// Snapshot taken when the editor opened, compared against ``draft`` on cancel.
    @State private var originalDraft: TripDraft

    /// Drives the confirmation shown when cancelling with unsaved changes.
    @State private var showsDiscardConfirmation = false

    // MARK: - Init

    /// Creates the editor.
    ///
    /// - Parameter subject: The trip to edit, or ``TripEditorSubject/new`` to create one.
    init(subject: TripEditorSubject) {

        self.subject = subject
        let draft = TripDraft(subject: subject)
        self._draft = State(initialValue: draft)
        self._originalDraft = State(initialValue: draft)
    }

    // MARK: - Body

    var body: some View {

        NavigationStack {
            Form {
                titleSection
                datesSection
                countriesSection
                notesSection
            }
            .navigationTitle(subject.id == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .confirmationDialog("Discard changes?",
                                isPresented: $showsDiscardConfirmation,
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section("Title") {
            TextField("Trip name", text: $draft.title)
        }
    }

    /// Date range, hidden behind a toggle so a trip may carry no dates at all.
    @ViewBuilder
    private var datesSection: some View {
        Section("Dates") {

            Toggle("Set dates", isOn: $draft.hasDates.animation())

            if draft.hasDates {
                DatePicker("From", selection: $draft.startDate, displayedComponents: .date)
                    .onChange(of: draft.startDate) { _, newValue in
                        // Keep the range valid rather than rejecting it after the fact.
                        if draft.endDate < newValue { draft.endDate = newValue }
                    }

                DatePicker("To", selection: $draft.endDate,
                           in: draft.startDate..., displayedComponents: .date)
            }
        }
    }

    /// Assigned countries: a link into the picker plus a summary of the selection.
    private var countriesSection: some View {
        Section("Countries") {

            NavigationLink {
                TripCountryPickerView(selectedCodes: $draft.countryCodes)
            } label: {
                HStack {
                    Text("Assigned countries")
                    Spacer()
                    Text(verbatim: "\(draft.countryCodes.count)")
                        .foregroundStyle(.secondary)
                }
            }

            if !selectedCountries.isEmpty {
                Text(selectedCountries.map(\.displayName).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {

        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { cancel() }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
        }
    }

    // MARK: - Helpers

    /// The selected countries, resolved from ``TripDraft/countryCodes`` and in the order the
    /// user reads them, which is not the order the query sorted them in.
    private var selectedCountries: [Country] {
        allCountries.filter { draft.countryCodes.contains($0.iso2) }.sortedByDisplayName()
    }

    // MARK: - Actions

    /// Closes the editor, asking first when the draft differs from what it started as.
    private func cancel() {

        guard draft != originalDraft else {
            dismiss()
            return
        }
        showsDiscardConfirmation = true
    }

    /// Writes the draft to the store and marks the assigned countries as visited.
    ///
    /// - Note: A new trip is inserted here and not before, so cancelling leaves no empty trip
    ///   behind.
    private func save() {

        let trip: Trip

        switch subject {
        case .new:
            trip = Trip()
            modelContext.insert(trip)
        case .existing(let existing):
            trip = existing
        }

        trip.title = trimmedOrNil(draft.title)
        trip.notes = trimmedOrNil(draft.notes)
        trip.startDate = draft.hasDates ? draft.startDate : nil
        trip.endDate = draft.hasDates ? draft.endDate : nil

        let countries = selectedCountries
        trip.countries = countries

        // Having been on a trip is what "visited" means, so the assignment implies the status.
        for country in countries {
            try? CountryStatusService.setStatus(.visited, for: country, in: modelContext)
        }

        try? modelContext.save()
        dismiss()
    }

    /// Trims `text` and turns an empty result into `nil`, which is how the model stores "unset".
    ///
    /// - Parameter text: The raw field contents.
    /// - Returns: The trimmed text, or `nil` when nothing is left.
    private func trimmedOrNil(_ text: String) -> String? {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    TripEditorView(subject: .new)
        .modelContainer(for: [Country.self, Trip.self], inMemory: true)
}
