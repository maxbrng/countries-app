import Foundation
import SwiftData

// Lightweight DTO matching countries.min.json schema
struct CountrySeed: Decodable {
    let name: String
    let iso2: String
    let continent: String?
}

@MainActor
func seedCountriesIfNeeded(context: ModelContext) throws {
    // If there are already countries, skip seeding
    let existingCount = try context.fetchCount(FetchDescriptor<Country>())
    guard existingCount == 0 else { return }

    guard let url = Bundle.main.url(forResource: "countries.min", withExtension: "json") else {
        throw NSError(domain: "Seed", code: 1, userInfo: [NSLocalizedDescriptionKey: "countries.min.json not found in bundle"]) }

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    let seeds = try decoder.decode([CountrySeed].self, from: data)

    for item in seeds {
        // Initialize your Country model based on your schema
        // Assuming Country has init(name: String, iso2: String, continent: String?)
        let country = Country(name: item.name, iso2: item.iso2, continent: item.continent)
        context.insert(country)
    }
    try context.save()
}
