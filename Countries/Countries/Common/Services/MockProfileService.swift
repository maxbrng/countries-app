//
//  MockProfileService.swift
//  Countries
//
//  Created by Max Breuning on 22.01.26.
//
//  Applies the selected mock profile to the SwiftData store:
//  - updates Country.status (visited/wishlist)
//  - recreates mock trips (1 trip per visited country)
//  - auto-derives UserPreferences from history (unless user customized)
//

import Foundation
import SwiftData

struct MockProfiles {
    
    // MARK: - Persona 1: “European City + Food + Culture”
    // Story: travels mainly Europe, lots of city trips + culture + food, mild/warm climate.
    // Recommender should show:
    // - Similar: Portugal, Austria, Hungary, Czechia
    // - Diversity boost: Mexico, Japan, Vietnam (new continents)
    static let user1Visited: Set<String> = [
        "ES", // Spain
        "IT", // Italy
        "FR", // France
        "PT", // Portugal
        "GR"  // Greece
    ]
    static let user1Wishlist: Set<String> = [
        "JP", // Japan (culture/food, new continent)
        "MX", // Mexico (food/beach, diversity)
        "TR", // Turkey (culture/food, similar-ish)
        "AT", // Austria (culture/city, similar)
        "CZ"  // Czechia (city/culture, similar)
    ]
    
    // MARK: - Persona 2: “SEA Budget Beach + Food (Backpacker/Nomad vibes)”
    // Story: prefers tropical/warm, cheap/medium cost, beach + food + adventure.
    // Recommender should show:
    // - Similar: Philippines, Malaysia, Sri Lanka
    // - Diversity boost: Colombia, Morocco (still warm, but new region)
    static let user2Visited: Set<String> = [
        "TH", // Thailand
        "VN", // Vietnam
        "ID", // Indonesia
        "MY", // Malaysia
        "PH"  // Philippines
    ]
    static let user2Wishlist: Set<String> = [
        "LK", // Sri Lanka (beach + food + warm)
        "SG", // Singapore (city/food, slightly pricier)
        "MX", // Mexico (warm, food, new continent)
        "MA", // Morocco (warm/mixed, culture/food)
        "CO"  // Colombia (warm, nature/adventure)
    ]
    
    // MARK: - Persona 3: “Outdoors + Hiking + Nature (Alps/Nordics)”
    // Story: nature/hiking, colder/mild climates, very safe countries, higher cost accepted.
    // Recommender should show:
    // - Similar: Austria, Sweden, Finland
    // - Diversity boost: New Zealand, Canada (nature, safe, new continents)
    static let user3Visited: Set<String> = [
        "CH", // Switzerland
        "AT", // Austria
        "NO", // Norway
        "IS", // Iceland
        "SE"  // Sweden
    ]
    static let user3Wishlist: Set<String> = [
        "FI", // Finland (similar nordic)
        "CA", // Canada (nature/hiking, diversity)
        "NZ", // New Zealand (nature/adventure, diversity)
        "JP", // Japan (safe, culture + nature, diversity)
        "DE"  // Germany (safe, hiking/city mix)
    ]
    
    // MARK: - Status mapping (FIXED!)
    static func status(for iso2: String, selectedUser: Int) -> CountryStatus {
        let code = iso2.uppercased()
        
        switch selectedUser {
        case 0: // user1
            if user1Visited.contains(code) { return .visited }
            if user1Wishlist.contains(code) { return .wishlist }
            
        case 1: // user2
            if user2Visited.contains(code) { return .visited }
            if user2Wishlist.contains(code) { return .wishlist }
            
        case 2: // user3
            if user3Visited.contains(code) { return .visited }
            if user3Wishlist.contains(code) { return .wishlist }
            
        default:
            break
        }
        
        return .none
    }
}


@MainActor
enum MockProfileService {
    
    static func applySelectedMockProfile(in context: ModelContext) throws {
        let profileID = UserDefaults.standard.integer(forKey: "selectedMockUser")
        print("profileID", profileID)
        try apply(profileID: profileID, in: context)
    }
    
    static func apply(profileID: Int, in context: ModelContext) throws {
        try updateCountryStatuses(for: profileID, in: context)
        try rebuildMockTripsFromVisitedCountries(in: context)
        try upsertAutoDerivedPreferences(profileID: profileID, in: context)
        print("apply", profileID)
        try context.save()
    }
    
    // MARK: - Countries
    
    private static func updateCountryStatuses(for profileID: Int, in context: ModelContext) throws {
        let countries = try context.fetch(FetchDescriptor<Country>())
        for country in countries {
            country.status = MockProfiles.status(for: country.iso2, selectedUser: profileID)
        }
    }
    
    // MARK: - Trips
    
    private static func rebuildMockTripsFromVisitedCountries(in context: ModelContext) throws {
        // Demo behavior: delete existing trips and create new ones.
        let oldTrips = try context.fetch(FetchDescriptor<Trip>())
        for trip in oldTrips { context.delete(trip) }
        
        let allCountries = try context.fetch(FetchDescriptor<Country>())
        let visitedCountries = allCountries.filter { $0.status == .visited }
        
        let now = Date()
        var dayOffset = 0
        
        for country in visitedCountries {
            let start = Calendar.current.date(byAdding: .day, value: -(dayOffset + 12), to: now)!
            let end = Calendar.current.date(byAdding: .day, value: -(dayOffset + 9), to: now)!
            
            let trip = Trip(
                title: "Trip to \(country.nameEnglish)",
                startDate: start,
                endDate: end,
                duration: TravelDuration.derived(from: start, to: end),
                season: Season.from(date: start),
                countries: [country],
                notes: nil
            )
            
            context.insert(trip)
            dayOffset += 21
        }
    }
    
    // MARK: - Preferences
    
    private static func upsertAutoDerivedPreferences(profileID: Int, in context: ModelContext) throws {
        
        let prefs = try fetchOrCreatePreferences(profileID: profileID, in: context)
        print("prefs", prefs)
        
        guard prefs.userDidCustomize == false else { return }
        
        let trips = try context.fetch(FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        ))
        
        let allCountries = try context.fetch(FetchDescriptor<Country>())
        let visitedCountries = allCountries.filter { $0.status == .visited }
        let wishlistedCountries = allCountries.filter { $0.status == .wishlist }

        let auto = PreferenceDerivationService.derive(
            visitedCountries: visitedCountries,
            wishlistedCountries: wishlistedCountries,
            trips: trips
        )
        
        prefs.desiredTags = auto.desiredTags
        prefs.preferredClimate = auto.preferredClimate
        prefs.maxCostLevel = auto.maxCostLevel
        prefs.minSafety = auto.minSafety
        prefs.preferredDuration = auto.preferredDuration
        prefs.preferredSeason = auto.preferredSeason
        prefs.recommendationMode = .balanced
        prefs.updatedAt = .now
    }
    
    private static func fetchOrCreatePreferences(profileID: Int, in context: ModelContext) throws -> UserPreferences {
        //        let descriptor = FetchDescriptor<UserPreferences>(
        //            predicate: #Predicate { $0.profileKey == profileID }
        //        )
        let all = try context.fetch(FetchDescriptor<UserPreferences>())
        print("preferences", all.count)
        
        if let existing = all.first(where: { $0.profileKey == profileID }) {
            return existing
        }
        
        let created = UserPreferences(profileKey: profileID)
        context.insert(created)
        
        return created
    }
    
    static func handleCountryStatusChange(for country: Country, in context: ModelContext) throws {
        
        let profileID = UserDefaults.standard.integer(forKey: "selectedMockUser")
        
        try syncMockTripsAfterStatusChange(for: country, in: context)
        try upsertAutoDerivedPreferences(profileID: profileID, in: context)
        
        try context.save()
    }
    
    // MARK: - Trip Sync for manual status changes (Mock behavior)
    
    private static func syncMockTripsAfterStatusChange(for country: Country, in context: ModelContext) throws {
        
        // fetch all trips once (small dataset -> easy)
        let allTrips = try context.fetch(FetchDescriptor<Trip>())
        
        let tripsContainingCountry = allTrips.filter { trip in
            trip.countries.contains(where: { $0.iso2 == country.iso2 })
        }
        
        if country.status == .visited {
            // Ensure there is at least one trip for this country
            guard tripsContainingCountry.isEmpty else { return }
            
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -10, to: now)!
            let end = Calendar.current.date(byAdding: .day, value: -7, to: now)!
            
            let newTrip = Trip(
                title: "Trip to \(country.nameEnglish)",
                startDate: start,
                endDate: end,
                duration: TravelDuration.derived(from: start, to: end),
                season: Season.from(date: start),
                countries: [country],
                notes: nil
            )
            
            context.insert(newTrip)
        } else {
            // If user un-visits a country, remove mock trips that are ONLY for this country.
            // (Keep multi-country trips untouched.)
            for trip in tripsContainingCountry {
                let isOnlyThisCountry = trip.countries.count == 1 && trip.countries.first?.iso2 == country.iso2
                let looksLikeMockTrip = (trip.title ?? "").hasPrefix("Trip to ")
                if isOnlyThisCountry && looksLikeMockTrip {
                    context.delete(trip)
                }
            }
        }
    }
}

// MARK: - Small helper

private extension TravelDuration {
    static func derived(from start: Date, to end: Date) -> TravelDuration {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case 0...2: return .weekend
        case 3...6: return .short
        case 7...13: return .medium
        case 14...29: return .long
        default: return .nomad
        }
    }
}
