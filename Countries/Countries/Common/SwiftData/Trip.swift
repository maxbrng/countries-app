//
//  Trip.swift
//  Countries
//
//  Created by Max Breuning on 19.01.26.
//

import SwiftData
import Foundation

@Model
final class Trip {
    
    var title: String?
    var startDate: Date?
    var endDate: Date?

    // Derived context (for recommender + analytics)
    var duration: TravelDuration?     // can be derived from dates as well
    var season: Season?               // can be derived from startDate
    
    @Relationship(deleteRule: .nullify, inverse: \Country.trips)
    var countries: [Country]
    // Optional: notes/photos later
    var notes: String?

    init(
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        duration: TravelDuration? = nil,
        season: Season? = nil,
        countries: [Country] = [],
        notes: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.season = season
        self.countries = countries
        self.notes = notes
    }
}
