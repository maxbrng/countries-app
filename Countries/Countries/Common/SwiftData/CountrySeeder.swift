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
    
    let id: Int?
    let alpha2: String
    let alpha3: String?

    let meta: Meta

    let hasSourceTranslations: Bool
    let isUN: Bool

    let translations: [String: String]

    struct Meta: Decodable {
        let name: String
        let native: String?
        let phone: [Int]?
        let continent: String?
        let capital: String?
        let currency: [String]?
        let languages: [String]?
    }
}


@MainActor
struct CountrySeeder {

    static func seedIfNeeded(in context: ModelContext) throws {

        let existing = try context.fetchCount(FetchDescriptor<Country>())
        guard existing == 0 else { return }

        guard let url = Bundle.main.url(forResource: "countries.translations", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([CountryJSON].self, from: data)

        for item in decoded {

            context.insert(
                Country(
                    iso2: item.alpha2.uppercased(),
                    iso3: item.alpha3,
                    nameEnglish: item.meta.name,
                    nativeName: item.meta.native,
                    continent: item.meta.continent,
                    capital: item.meta.capital,
                    phoneCodes: item.meta.phone ?? [],
                    currencies: item.meta.currency ?? [],
                    languages: item.meta.languages ?? [],
                    isUNMember: item.isUN,
                    dataHasSourceTranslation: item.hasSourceTranslations,
                    translations: item.translations
                )
            )
        }

        try context.save()
    }
}
