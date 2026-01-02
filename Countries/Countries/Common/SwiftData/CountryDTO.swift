//
//  CountryDTO.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//


import Foundation

struct CountryDTO: Decodable {
    let iso2: String
    let name: String
    let continent: String?
    let region: String?
}

struct CountriesSeed: Decodable {
    let countries: [CountryDTO]
}

struct CountriesSeedWrapper: Decodable {
    let data: CountriesSeed?
}
