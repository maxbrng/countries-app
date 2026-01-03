//
//  CountryCardView.swift
//  Countries
//
//  Created by Max Breuning on 03.01.26.
//

import SwiftUI

struct CountryCardView: View {
    
    let item: CountryRecommendation
    let height: CGFloat
    
    var body: some View {
        
        ZStack(alignment: .bottomLeading) {
            
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 10) {
                
                HStack(spacing: 10) {
                    
                    Text(item.emoji)
                        .font(.system(size: 40))
                    Text(item.name)
                        .font(.title.bold())
                }
                
                Text(item.subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer(minLength: 0)
                
                HStack {
                    
                    Text("Tap für Details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(radius: 16, y: 10)
    }
}
