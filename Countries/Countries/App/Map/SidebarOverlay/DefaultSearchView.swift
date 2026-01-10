//
//  DefaultSearchView.swift
//  Countries
//
//  Created by Max Breuning on 09.01.26.
//


import SwiftUI

// Diese View wird im permanenten Sheet angezeigt, 
// wenn selectedCountry == nil und showAppearancePanel == false ist.
struct DefaultSearchView: View {
    var body: some View {
        VStack(spacing: 15) {
            // Der typische "Grabber" oben am Sheet
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            // Die simulierte Searchbar (deine Inspo)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("Suchen...")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Hier könnten Favoriten oder letzte Suchen stehen
            List {
                Section(header: Text("Zuletzt gesucht")) {
                    Label("Deutschland", systemImage: "clock")
                    Label("Frankreich", systemImage: "clock")
                }
            }
            .listStyle(.plain)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
