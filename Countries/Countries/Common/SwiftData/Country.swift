//
//  Country.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//

import SwiftData

enum CountryStatus: Int, Codable {
    case none = 0
    case visited = 1
    case wishlist = 2
}

@Model
final class Country {
    @Attribute(.unique) var iso2: String      // "DE"
    var name: String                          // "Germany"
    var continent: String?
    var region: String?

    var statusRaw: Int                        // gespeichert als Int
    var status: CountryStatus {
        get { CountryStatus(rawValue: statusRaw) ?? .none }
        set { statusRaw = newValue.rawValue }
    }
    var notes: String?

    init(iso2: String, name: String, continent: String? = nil, status: CountryStatus = .none, region: String? = nil, notes: String? = nil) {
        self.iso2 = iso2.uppercased()
        self.name = name
        self.continent = continent
        self.region = region
        self.statusRaw = status.rawValue
        self.notes = notes
    }
}
