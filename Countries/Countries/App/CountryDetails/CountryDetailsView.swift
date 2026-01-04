//
//  CountryDetailsView.swift
//  Countries
//
//  Created by Max Breuning on 04.01.26.
//

import SwiftUI
import SwiftData

struct CountryDetailsView: View {
    @Environment(\.modelContext) private var modelContext

    let country: Country
    
    @State private var showingNotesEditor = false
    
    var body: some View {
        
        ScrollView {
            
            VStack(alignment: .leading, spacing: 16) {
                
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
        
        HStack(alignment: .center, spacing: 16) {
            
            Image(country.iso2.lowercased())
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .frame(maxWidth: 80, maxHeight: 56)
                
            VStack(alignment: .leading, spacing: 6) {
                Text(country.nameEnglish)
                    .font(.title2).fontWeight(.semibold)
                if let native = country.nativeName, !native.isEmpty {
                    Text(native)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    badge(for: country.status)
                    if country.isUNMember {
                        Label("UN Member", systemImage: "globe")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.15))
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
        VStack(alignment: .leading, spacing: 12) {
            
            if let nativeName = country.nativeName {
                infoRow(title: "Native Name", value: nativeName)
            }
            
            if let continent = country.continent {
                infoRow(title: "Continent", value: continent)
            }
            
            if let capital = country.capital, !capital.isEmpty {
                infoRow(title: "Capital", value: capital)
            }
            
            if !country.currencies.isEmpty {
                infoRow(title: "Currencies", value: country.currencies.joined(separator: ", "))
            }
            
            if !country.languages.isEmpty {
                infoRow(title: "Languages", value: country.languages.joined(separator: ", "))
            }
            
            if !country.currencies.isEmpty {
                infoRow(title: "Currencies", value: country.currencies.joined(separator: ", "))
            }
            
            if !country.phoneCodes.isEmpty {
                let codes = country.phoneCodes.map { "+\($0)" }.joined(separator: ", ")
                infoRow(title: "Phone Codes", value: codes)
            }
            
            if let iso3 = country.iso3 {
                infoRow(title: "ISO3", value: iso3)
            }
            
            infoRow(title: "ISO2", value: country.iso2)
        }
    }

    // MARK: - Notes
    private func notesSection(text: String) -> some View {
        
        VStack(alignment: .leading, spacing: 8) {
            
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
                Label(country.status == .visited ? "Visited" : "Mark Visited", systemImage: country.status == .visited ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .tint(.green)

            Button {
                toggleStatus(.wishlist)
            } label: {
                Label(country.status == .wishlist ? "On Wishlist" : "Add to Wishlist", systemImage: country.status == .wishlist ? "star.fill" : "star")
            }
            .tint(.blue)
        }
    }

    private func toggleStatus(_ newStatus: CountryStatus) {
        if country.status == newStatus {
            country.status = .none
        } else {
            country.status = newStatus
        }
        try? modelContext.save()
    }

    // MARK: - Helpers
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func badge(for status: CountryStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .visited:
            Text("Visited")
                .font(.caption)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
        case .wishlist:
            Text("Wishlist")
                .font(.caption)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(.blue.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}

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
    Text("CountryDetailsView Preview")
}

