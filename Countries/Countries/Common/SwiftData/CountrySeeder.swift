//
//  CountrySeeder.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//

import Foundation
import SwiftData

// JSON-DTO: Data Transfer Object um die items aus der JSON eins zu eins zu übertragen
struct CountryJSON: Decodable {
    let name: String
    let native: String?
    let phone: [Int]?
    let continent: String?
    let capital: String?
    let currency: [String]?
    let languages: [String]?
}


@MainActor
struct CountrySeeder {
    
    static func seedIfNeeded(in context: ModelContext) throws {
        
        let existing = try context.fetchCount(FetchDescriptor<Country>())
        guard existing == 0 else { return }
        
        guard let url = Bundle.main.url(forResource: "countries.min", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: CountryJSON].self, from: data)
        
        for (iso2, json) in decoded {
            context.insert(
                Country(
                    iso2: iso2,
                    name: json.name,
                    nativeName: json.native,
                    continent: json.continent,
                    capital: json.capital,
                    phoneCodes: json.phone ?? [],
                    currencies: json.currency ?? [],
                    languages: json.languages ?? [],
                    status: .none
                )
                    )
                }
        
        try context.save()
    }
}
