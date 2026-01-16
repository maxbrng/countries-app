//
//  StatView.swift
//  Countries
//
//  Created by Max Breuning on 15.01.26.
//

import SwiftUI


struct StatView: View {
    
    @ObservedObject var viewModel: MainScreenViewModel
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 0) {
            statistic(currentValue: viewModel.countriesVisited,
                      maxValue: viewModel.totalCountries,
                      text: "countries",
                      graphVisualization: false)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: viewModel.countriesVisited,
                      maxValue: viewModel.totalCountries,
                      text: "of the world",
                      graphVisualization: true)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: viewModel.continentsVisited,
                      maxValue: viewModel.totalContinents,
                      text: "continents",
                      graphVisualization: false)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        
    }
    
    @ViewBuilder
    func statistic(currentValue: Double,
                   maxValue: Double,
                   text: String,
                   graphVisualization: Bool) -> some View {
        
        VStack {
            
            if graphVisualization {
                let progress = max(0, min(1, currentValue / maxValue))
                let countryPercentage = progress * 100.0
                let text = String(format: "%.0f%%", countryPercentage)
                
                Gauge(value: progress) {
                    Text(verbatim: text)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .gaugeStyle(CircularStrokeGaugeStyle(lineWidth: 8))
                .frame(width: 60, height: 60)
                .padding(.bottom, 4)
                
            } else {
                
                Text("\(Int(currentValue))/\(Int(maxValue))")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
