//
//  Country.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//

import SwiftData

import SwiftData

enum CountryStatus: Int, Codable, CaseIterable {
    case none = 0
    case visited = 1
    case wishlist = 2
}

@Model
final class Country {

    @Attribute(.unique) var iso2: String   // "DE"

    var name: String
    var nativeName: String?
    var continent: String?
    var capital: String?

    var phoneCodes: [Int]
    var currencies: [String]
    var languages: [String]

    var status: CountryStatus
    var notes: String?

    init(
        iso2: String,
        name: String,
        nativeName: String? = nil,
        continent: String? = nil,
        capital: String? = nil,
        phoneCodes: [Int] = [],
        currencies: [String] = [],
        languages: [String] = [],
        status: CountryStatus = .none,
        notes: String? = nil
    ) {
        self.iso2 = iso2.uppercased()
        self.name = name
        self.nativeName = nativeName
        self.continent = continent
        self.capital = capital
        self.phoneCodes = phoneCodes
        self.currencies = currencies
        self.languages = languages
        self.status = status
        self.notes = notes
    }
}

