//
//  CountrySeeder.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//

import Foundation
import SwiftData

struct MockProfiles {
    static let user1Visited: Set<String> = ["US", "DE", "FR", "JP", "BR"]
    static let user1Wishlist: Set<String> = ["NZ", "CA", "NO", "ZA"]

    static let user2Visited: Set<String> = ["IN", "CN", "TH", "VN", "ID"]
    static let user2Wishlist: Set<String> = ["AU", "MX", "ES", "PT"]

    static let user3Visited: Set<String> = ["IT", "GR", "TR", "EG"]
    static let user3Wishlist: Set<String> = ["AR", "CL", "PE", "CO"]

    static func status(for iso2: String, selectedUser: Int) -> CountryStatus {
        let code = iso2.uppercased()
        switch selectedUser {
        case 1:
            if user2Visited.contains(code) { return .visited }
            if user2Wishlist.contains(code) { return .wishlist }
        case 2:
            if user3Visited.contains(code) { return .visited }
            if user3Wishlist.contains(code) { return .wishlist }
        default:
            if user1Visited.contains(code) { return .visited }
            if user1Wishlist.contains(code) { return .wishlist }
        }
        return .none
    }
}

// JSON-DTO: Data Transfer Object um die items aus der JSON eins zu eins zu übertragen
struct CountryJSON: Decodable {
    
    let id: Int?
    let alpha2: String
    let alpha3: String?

    let meta: Meta

    let hasSourceTranslations: Bool
    let isUN: Bool

    let translations: [String: String]
    
    let travelTags: [String]?
    let climateTags: [String]?
    let costLevel: Int?
    let safetyLevel: Int?
    let optimalTravelSeasons: [Int]?

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

private extension TravelTag {
    static func from(_ raw: String) -> TravelTag? {
        TravelTag(rawValue: raw.lowercased())
    }
}

private extension ClimateTag {
    static func from(_ raw: String) -> ClimateTag? {
        ClimateTag(rawValue: raw.lowercased())
    }
}

private extension CostLevel {
    static func from(_ raw: Int) -> CostLevel? {
        CostLevel(rawValue: raw)
    }
}

private extension SafetyLevel {
    static func from(_ raw: Int) -> SafetyLevel? {
        SafetyLevel(rawValue: raw)
    }
}

private extension Season {
    static func from(_ raw: Int) -> Season? {
        Season(rawValue: raw)
    }
}

@MainActor
struct CountrySeeder {

    static func applyMockProfile(in context: ModelContext) throws {
        // Read selected user
        let selectedUser = UserDefaults.standard.integer(forKey: "selectedMockUser")
        
        // Fetch all countries
        var descriptor = FetchDescriptor<Country>()
        descriptor.fetchLimit = nil
        let countries = try context.fetch(descriptor)
        
        // Reset all to .none
        for country in countries {
            country.status = .none
        }
        
        // Apply visited/wishlist from mock profile
        for country in countries {
            let newStatus = MockProfiles.status(for: country.iso2, selectedUser: selectedUser)
            country.status = newStatus
        }
        
        try context.save()
    }

    static func seedIfNeeded(in context: ModelContext) throws {

        let existing = try context.fetchCount(FetchDescriptor<Country>())
        guard existing == 0 else { return }
        
        guard let url = Bundle.main.url(forResource: "countries.enriched", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([CountryJSON].self, from: data)

        for item in decoded {

            let travelTags = (item.travelTags ?? [])
                .compactMap { TravelTag.from($0) }
            
            let climateTags = (item.climateTags ?? [])
                .compactMap { ClimateTag.from($0) }
            
            let costLevel = CostLevel.from(item.costLevel ?? CostLevel.medium.rawValue) ?? .medium
            let safetyLevel = SafetyLevel.from(item.safetyLevel ?? SafetyLevel.mixed.rawValue) ?? .mixed
            
//            let optimalSeasons = (item.optimalTravelSeasons ?? [])
//                .compactMap { Season.from($0) }
            
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
                    status: .none,
                    isUNMember: item.isUN,
                    dataHasSourceTranslation: item.hasSourceTranslations,
                    travelTags: travelTags,
                    climateTags: climateTags,
                    costLevel: costLevel,
                    safetyLevel: safetyLevel,
                    translations: item.translations
                )
            )
        }

        try context.save()
    }
}

