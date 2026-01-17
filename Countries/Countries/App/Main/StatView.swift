//
//  StatView.swift
//  Countries
//
//  Created by Max Breuning on 15.01.26.
//

import SwiftUI
import SwiftData

struct StatView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Country.iso2) private var allCountries: [Country]
    @AppStorage("showOnlyUNMembers") private var showOnlyUNMembers: Bool = false
    
    var body: some View {
        
        let source = showOnlyUNMembers ? allCountries.filter { $0.isUNMember } : allCountries

        let visited = source.filter { $0.status == .visited }
        let countriesVisited = Double(visited.count)
        let totalCountries = Double(source.count)

        let allContinents = Set(source.compactMap(\.continent))
        let totalContinents = Double(allContinents.count)
        let visitedContinents = Set(visited.compactMap(\.continent))
        let continentsVisited = Double(visitedContinents.count)
        
        HStack(alignment: .center, spacing: 0) {
            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      text: "countries",
                      graphVisualization: false)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      text: "of the world",
                      graphVisualization: true)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Divider()
            
            statistic(currentValue: continentsVisited,
                      maxValue: totalContinents,
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
