//
//  CountryIndex.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import Foundation
import SwiftData

/// Small value object that creates fast lookup tables from SwiftData `Country` records.
/// Keeps naming/logic identical between Flat + Globe maps.
// NOTE (Swift 6): `Country` (SwiftData model) is not Sendable.
// Therefore `CountryIndex` must not conform to `Sendable`.
struct CountryIndex {
    
    let countriesByISO2: [String: Country]
    let iso3ToIso2: [String: String]
    let nameToIso2: [String: String]

    init(countries: [Country]) {
        
        let normalizedCountries: [(String, Country)] = countries.map { ( $0.iso2.lowercased(), $0 ) }
        
        self.countriesByISO2 = Dictionary(uniqueKeysWithValues: normalizedCountries)

        self.iso3ToIso2 = Dictionary(uniqueKeysWithValues: countries.compactMap { country in
            
            guard let iso3 = country.iso3?.lowercased(),
                  !iso3.isEmpty
            else {
                return nil
            }
            
            return (iso3, country.iso2.lowercased())
        })

        self.nameToIso2 = Dictionary(uniqueKeysWithValues: countries.compactMap { country in
            
            let key = country.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            guard !key.isEmpty else {
                return nil
            }
            
            return (key, country.iso2.lowercased())
        })
    }
}

extension CountryIndex {
    /// A Sendable snapshot that can safely be used in background tasks.
    var resolverIndex: GeoJSONLoader.ResolverIndex {
        .init(iso3ToIso2: iso3ToIso2, nameToIso2: nameToIso2)
    }
}
