//
//  CountryRow.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI
import SwiftData

struct CountryRow: View {
    
    let country: Country
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack(spacing: 16) {
            Image(country.iso2.lowercased())
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .scaledToFit()
                .frame(maxWidth: 40, maxHeight: 30)
                
            
            VStack(alignment: .leading) {
                Text(country.nameEnglish)
                Text(country.iso2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            badge(for: country.status)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { toggleStatus(of: country, .visited) } label: {
                Label("Visited", systemImage: "checkmark.circle")
            }.tint(.green)
            
            Button { toggleStatus(of: country, .wishlist) } label: {
                Label("Wishlist", systemImage: "star")
            }.tint(.blue)
        }
    }
    
    private func toggleStatus(of country: Country, _ newStatus: CountryStatus) {
        country.status = (country.status == newStatus) ? .none : newStatus
        try? modelContext.save()
    }
    
    @ViewBuilder
    private func badge(for status: CountryStatus) -> some View {
        
        switch status {
        case .none:
            EmptyView()
            
        case .visited:
            Text("Visited")
                .padding(4)
                .padding(.horizontal, 6)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
            
        case .wishlist:
            Text("Wishlist")
                .padding(4)
                .padding(.horizontal, 6)
                .background(.blue.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}
