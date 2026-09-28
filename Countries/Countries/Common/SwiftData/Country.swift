//
//  Country.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//

import Foundation
import SwiftData

@Model
final class Country {

    @Attribute(.unique) var iso2: String   // "DE"
    var iso3: String?

    var nameEnglish: String
    var nativeName: String?
    var continent: String?
    var capital: String?

    var phoneCodes: [Int]
    var currencies: [String]
    var languages: [String]

    var status: CountryStatus
    var notes: String?
    
    var isUNMember: Bool
    var dataHadSourceTranslations: Bool // others had translations added with AI
    
    var travelTags: [TravelTag]
    var climateTags: [ClimateTag]
    var costLevel: CostLevel
    var safetyLevel: SafetyLevel
    
    
    @Relationship var trips: [Trip] = []
    
    @Attribute(.externalStorage) var translationsData: Data?

    init(
        iso2: String,
        iso3: String? = nil,
        nameEnglish: String,
        nativeName: String? = nil,
        continent: String? = nil,
        capital: String? = nil,
        phoneCodes: [Int] = [],
        currencies: [String] = [],
        languages: [String] = [],
        status: CountryStatus = .none,
        isUNMember: Bool,
        dataHasSourceTranslation: Bool,
        notes: String? = nil,
        travelTags: [TravelTag],
        climateTags: [ClimateTag],
        costLevel: CostLevel,
        safetyLevel: SafetyLevel,
        translations: [String: String]
    ) {
        self.iso2 = iso2.uppercased()
        self.iso3 = iso3
        self.nameEnglish = nameEnglish
        self.nativeName = nativeName
        self.continent = continent
        self.capital = capital
        self.phoneCodes = phoneCodes
        self.currencies = currencies
        self.languages = languages
        self.status = status
        self.isUNMember = isUNMember
        self.dataHadSourceTranslations = dataHasSourceTranslation
        self.notes = notes
        self.travelTags = travelTags
        self.climateTags = climateTags
        self.costLevel = costLevel
        self.safetyLevel = safetyLevel
        self.translationsData = try? JSONEncoder().encode(translations)
    }
    
    var localizedNames: [String: String] {
        
        get {
            guard let translationsData,
                  let dict = try? JSONDecoder().decode([String: String].self, from: translationsData)
            else { return [:] }
            return dict
        }
        set {
            translationsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    func displayName(preferredLanguageCodes: [String]) -> String {
        
        let dict = localizedNames
        
        for code in preferredLanguageCodes {
            if let hit = dict[code] { return hit }
            if let base = code.split(separator: "-").first.map(String.init),
               let hit = dict[base] { return hit }
        }
        
        return nameEnglish
    }
}

