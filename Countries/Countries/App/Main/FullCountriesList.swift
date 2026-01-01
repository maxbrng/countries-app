//
//  FullCountriesList.swift
//  Countries
//
//  Created by Max Breuning on 31.12.25.
//

import SwiftUI

struct FullCountriesList: View {
    
    @Binding var path: NavigationPath
    
      var body: some View {
          
          List {
              Text("Country")
          }
          .navigationTitle("All countries")
          .navigationBarTitleDisplayMode(.inline)
      }
  }
