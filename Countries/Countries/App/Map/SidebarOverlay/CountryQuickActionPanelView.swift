//
//  CountryQuickActionPanelView.swift
//  Countries
//
//  Created by Max Breuning on 08.01.26.
//


import SwiftUI
import SwiftData

struct CountryQuickActionPanelView: View {
    
    let country: Country
    let onClose: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var showDetailSheet = false
    
    var body: some View {
        
        VStack(spacing: 12) {
            
            actionButtons
            
            Button {
                showDetailSheet = true
            } label: {
                Label("Show Details", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .buttonStyle(.glass)
            .sheet(isPresented: $showDetailSheet) {
                CountryDetailsView(country: country)
                    .presentationDetents([.fraction(0.6), .fraction(0.8), .large])
            }
        }
        .padding()
    }
    
    private var actionButtons: some View {
        
        HStack(spacing: 12) {
            
            Button(action: { toggle(.visited) }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Visited")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .tint(.green)
            
            Button(action: { toggle(.wishlist) }) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Wishlist")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .tint(.blue)
        }
    }
    
    private func toggle(_ status: CountryStatus) {
        country.status = (country.status == status) ? .none : status
        try? modelContext.save()
    }
}
