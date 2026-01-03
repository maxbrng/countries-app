//
//  CountryCardView.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI

struct CountryDetailView: View {
    
    let item: CountryRecommendation
    
    var body: some View {
        
        VStack(spacing: 16) {
            Text(item.emoji).font(.system(size: 72))
            Text(item.name).font(.largeTitle.bold())
            Text(item.subtitle).font(.title3).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
