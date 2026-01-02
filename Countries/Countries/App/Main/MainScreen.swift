//
//  MainScreen.swift
//  Countries
//
//  Created by Max Breuning on 04.12.25.
//

import SwiftUI
import MapKit
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries", category: "MainScreen")

struct MainScreen: View {
    
    @Binding var path: NavigationPath
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasSeededCountries") private var hasSeededCountries: Bool = false
    
    @State private var countriesVisited: Double = 0
    @State private var continentsVisited: Double = 0
    @State private var totalCountries: Double = 0
    @State private var totalContinents: Double = 0
    
    @State private var visitedCountries: [Country] = []
    @State private var wishlistCountries: [Country] = []
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    
    var body: some View {
        
        ScrollView {
            LazyVStack(spacing: 40) {
                NavigationLink(value: AppRoute.mapScreen) {
                    Map()
                        .disabled(true)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40))
                        .padding(.top)
                }
                
                statView()
                
                countryCard()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Your Countries")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            do {
                try seedCountriesIfNeededLocal(context: modelContext)
                hasSeededCountries = true
                logger.info("✅ Seeding erfolgreich abgeschlossen. [\(#fileID):\(#line) \(#function)]")
            } catch {
                hasSeededCountries = true // avoid retry loop
                logger.error("❌ Seeding fehlgeschlagen. error=\(String(describing: error), privacy: .public) [\(#fileID):\(#line) \(#function)]")
            }
            await loadData()
        }
    }
    
    // MARK: - Seeding
    private struct CountrySeed: Decodable {
        let name: String
        let iso2: String? // Filled from dictionary key if missing in JSON
        let continent: String?
    }
    private struct CountriesSeed: Decodable {
        let countries: [CountrySeed]
    }

    @MainActor
    private func seedCountriesIfNeededLocal(context: ModelContext) throws {

        let existingCount = try context.fetchCount(FetchDescriptor<Country>())
        
        guard existingCount == 0 else {
            logger.notice("⏭️ Bereits vorhanden – Seeding übersprungen. [\(#fileID):\(#line) \(#function)]")
            return
        }
        
        guard let url = Bundle.main.url(forResource: "countries.min", withExtension: "json") else {
            logger.error("❌ Seed-Datei fehlt: countries.min.json [\(#fileID):\(#line) \(#function)]")
            throw NSError(domain: "Seed", code: 1, userInfo: [NSLocalizedDescriptionKey: "countries.min.json not found in bundle"]) }
        
        let data = try Data(contentsOf: url)
        logger.info("📦 JSON geladen: \(data.count, privacy: .public) Bytes [\(#fileID):\(#line) \(#function)]")
        let decoder = JSONDecoder()
        if let root = try? decoder.decode(CountriesSeed.self, from: data) {
            logger.info("📗 Wrapper dekodiert: \(root.countries.count, privacy: .public) Einträge [\(#fileID):\(#line) \(#function)]")
            try insertSeeds(root.countries, context: context)
        } else if let dict = try? decoder.decode([String: CountrySeed].self, from: data) {
            let mapped: [CountrySeed] = dict.map { (key, value) in
                CountrySeed(name: value.name, iso2: key, continent: value.continent)
            }
            logger.info("📘 Dictionary dekodiert: \(mapped.count, privacy: .public) Einträge [\(#fileID):\(#line) \(#function)]")
            try insertSeeds(mapped, context: context)
        } else if let array = try? decoder.decode([CountrySeed].self, from: data) {
            logger.info("📙 Array dekodiert: \(array.count, privacy: .public) Einträge [\(#fileID):\(#line) \(#function)]")
            try insertSeeds(array, context: context)
        } else {
            logger.error("❌ Dekodierung fehlgeschlagen – unbekanntes JSON-Format. [\(#fileID):\(#line) \(#function)]")
            throw NSError(domain: "Seed", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON format not recognized (wrapper, dict, or array)"])
        }
    }
    
    private func insertSeeds(_ seeds: [CountrySeed], context: ModelContext) throws {
        var inserted = 0
        for item in seeds {
            guard let code = item.iso2, !code.isEmpty else {
                logger.error("⚠️ Eintrag ohne ISO2 übersprungen. name=\(item.name, privacy: .public) [\(#fileID):\(#line) \(#function)]")
                continue
            }
            let country = Country(iso2: code, name: item.name, continent: item.continent)
            context.insert(country)
            inserted += 1
        }
        try context.save()
        logger.info("✅ Gespeichert. Eingefügt=\(inserted, privacy: .public) [\(#fileID):\(#line) \(#function)]")
    }
    
    // MARK: - Data Loading
    @MainActor
    private func loadData() async {
        
        let repository = CountryRepository(context: modelContext)
        
        do {
            // Stats
            let stats = try repository.stats()
            logger.info("📊 Stats: visited=\(stats.visited, privacy: .public) wishlist=\(stats.wishlist, privacy: .public) total=\(stats.total, privacy: .public) [\(#fileID):\(#line) \(#function)]")
            countriesVisited = Double(stats.visited)
            totalCountries = Double(stats.total)

            // Fetch visited and wishlist countries
            let visitedList = try repository.fetchAll(search: nil, filter: .visited, sortAscending: true)
            let wishlistList = try repository.fetchAll(search: nil, filter: .wishlist, sortAscending: true)

            // Distinct continents from visited
            let continentSet = Set(visitedList.compactMap { $0.continent })
            continentsVisited = Double(continentSet.count)

            // Total distinct continents across all countries in the database
            let allCountries = try repository.fetchAll(search: nil, filter: .all, sortAscending: true)
            let allContinentSet = Set(allCountries.compactMap { $0.continent })
            totalContinents = Double(allContinentSet.count)

            visitedCountries = visitedList
            wishlistCountries = wishlistList
        } catch {
            logger.error("❌ Laden fehlgeschlagen. error=\(String(describing: error), privacy: .public) [\(#fileID):\(#line) \(#function)]")
            // Basic error handling: reset to safe defaults
            countriesVisited = 0
            continentsVisited = 0
            visitedCountries = []
            wishlistCountries = []
        }
    }
    
    // MARK: - Statistic
    
    @ViewBuilder
    func statView() -> some View {
        
        HStack(alignment: .center, spacing: 0) {
            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      text: "countries",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: countriesVisited,
                      maxValue: totalCountries,
                      text: "of the world",
                      graphVisualization: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Divider()

            statistic(currentValue: continentsVisited,
                      maxValue: totalContinents,
                      text: "continents",
                      graphVisualization: false)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        
    }
    
    @ViewBuilder
    func statistic(currentValue: Double,
                   maxValue: Double,
                   text: String,
                   graphVisualization: Bool) -> some View {
        
        VStack {
            
            if graphVisualization {
                let progress = max(0, min(1, currentValue / maxValue))
                let countryPercentage = progress * 100.0
                let text = String(format: "%.0f%%", countryPercentage)
                
                Gauge(value: progress) {
                    Text(verbatim: text)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .gaugeStyle(CircularStrokeGaugeStyle(lineWidth: 8))
                .frame(width: 60, height: 60)
                .padding(.bottom, 4)
                
            } else {
                
                Text("\(Int(currentValue))/\(Int(maxValue))")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - CountryCard
    
    @ViewBuilder
    func countryCard() -> some View {
        
        NavigationLink(value: AppRoute.fullCountryList) {
            
            VStack(alignment: .leading, spacing: 16) {
                
                Text(verbatim: "Countries & Territories")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(alignment: .top, spacing: 24) {
                    countryPreviewList(for: "Visited", countries: visitedCountries)
                    
                    countryPreviewList(for: "On Wishlist", countries: wishlistCountries)
                }
                
                Divider()
                
                cardDetailLink()
            }
        }
        .tint(.primary)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 36))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func countryPreviewList(for text: String,
                                    countries: [Country]) -> some View {
        
        let remainingVisited = max(0, countries.count - 3)
        
        VStack(alignment: .leading, spacing: 8) {
            
            HStack(spacing: 6) {
                
                Text(verbatim: "\(countries.count)")
                    .font(.headline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(verbatim: text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                
                ForEach(countries.prefix(3), id: \.iso2) { item in
                    
                    HStack(spacing: 8) {
                        
                        Image(item.iso2.lowercased())
                            .resizable()
                            .scaledToFit()
                            .frame(height: 10)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        
                        Text(item.name)
                            .foregroundStyle(.primary)
                    }
                    .font(.footnote)
                }
                if remainingVisited > 0 {
                    Text("+\(remainingVisited) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func cardDetailLink() -> some View {
        
        HStack {
            Text("See Full List")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct CircularStrokeGaugeStyle: GaugeStyle {
    var lineWidth: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)

            let progress = configuration.value

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))

            configuration.label
        }
    }
}

#Preview {
    MainScreen(path: .constant(NavigationPath()))
}


