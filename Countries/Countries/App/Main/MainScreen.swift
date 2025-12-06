//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit

struct MainScreen: View {
    
    @State private var showFullMap = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    
    var body: some View {
        
        List() {
//            Button {
//                showFullMap = true
//            } label: {
                Map()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
//                    .padding(.horizontal, 20)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
//            }
            
            statView()
                .listRowSeparator(.hidden)
                .allowsTightening(false)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Your Journey")
        .listStyle(.plain)
        .selectionDisabled(true)
        
    }
    
    @ViewBuilder
    func statView() -> some View {
        
        HStack(alignment: .center, spacing: 15) {
            
            statistic()
                
            Divider()
            
            statistic()
            
            Divider()
                
            statistic()
        }
        .frame(width: .infinity)
        
    }
    
    @ViewBuilder
    func statistic() -> some View {
        
        VStack {
            Text("5/195")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .background(Color.blue)
                .cornerRadius(10)
            
            Text("Countries Visited")
                .font(.caption)
        }
    }
}



#Preview {
    MainScreen()
}


