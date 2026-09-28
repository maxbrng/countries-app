//
//  CountryDisplayNameTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation
import Testing
@testable import Countries

/// Covers which name a country answers to, and which one it is filed under.
///
/// The failure this guards against is quiet: a missing translation would simply show the
/// English name, and a search that only looks at the English name would find nothing for a
/// word the user can see on screen.
@MainActor
struct CountryDisplayNameTests {

    // MARK: - Fixture

    /// Builds a country with only the fields these tests care about filled in.
    ///
    /// - Parameters:
    ///   - iso2: The country code.
    ///   - iso3: The three-letter code.
    ///   - name: The English name.
    ///   - translations: Localized names by language code.
    private func makeCountry(iso2: String,
                             iso3: String? = nil,
                             name: String,
                             translations: [String: String] = [:]) -> Country {

        Country(iso2: iso2,
                iso3: iso3,
                nameEnglish: name,
                status: .none,
                isUNMember: true,
                dataHasSourceTranslation: true,
                travelTags: [],
                climateTags: [],
                costLevel: .medium,
                safetyLevel: .safe,
                translations: translations)
    }

    // MARK: - Resolution

    @Test
    func test_displayName_withATranslationForTheLanguage_usesIt() {

        // Arrange
        let country = makeCountry(iso2: "FR", name: "France",
                                  translations: ["de": "Frankreich", "en": "France"])

        // Act
        let name = country.displayName(preferredLanguageCodes: ["de"])

        // Assert
        #expect(name == "Frankreich")
    }

    @Test
    func test_displayName_withARegionalLanguageCode_fallsBackToTheBaseLanguage() {

        // Arrange
        // A device set to Austrian German asks for "de-AT"; the data only carries "de".
        let country = makeCountry(iso2: "FR", name: "France", translations: ["de": "Frankreich"])

        // Act
        let name = country.displayName(preferredLanguageCodes: ["de-AT"])

        // Assert
        #expect(name == "Frankreich")
    }

    @Test
    func test_displayName_withoutATranslation_fallsBackToEnglishRatherThanNothing() {

        // Arrange
        let country = makeCountry(iso2: "XK", name: "Kosovo", translations: ["fr": "Kosovo"])

        // Act
        let name = country.displayName(preferredLanguageCodes: ["de", "en"])

        // Assert
        #expect(name == "Kosovo")
    }

    @Test
    func test_displayName_prefersTheFirstLanguageItCanServe() {

        // Arrange
        let country = makeCountry(iso2: "ES", name: "Spain",
                                  translations: ["de": "Spanien", "fr": "Espagne"])

        // Act
        let name = country.displayName(preferredLanguageCodes: ["it", "fr", "de"])

        // Assert
        // Italian is missing, so French wins — not German, although German is also present.
        #expect(name == "Espagne")
    }

    // MARK: - Search

    @Test
    func test_matches_findsTheCountryByItsEnglishName() {

        // Arrange
        let country = makeCountry(iso2: "FR", iso3: "FRA", name: "France",
                                  translations: ["de": "Frankreich"])

        // Act & Assert
        #expect(country.matches(searchQuery: "fran"))
    }

    @Test
    func test_matches_findsTheCountryByItsIsoCodes() {

        // Arrange
        let country = makeCountry(iso2: "FR", iso3: "FRA", name: "France")

        // Act & Assert
        #expect(country.matches(searchQuery: "fr"))
        #expect(country.matches(searchQuery: "fra"))
    }

    @Test
    func test_matches_ignoresCaseAndSurroundingWhitespace() {

        // Arrange
        let country = makeCountry(iso2: "FR", name: "France")

        // Act & Assert
        #expect(country.matches(searchQuery: "  FRANCE "))
    }

    @Test
    func test_matches_withAnEmptyQuery_letsEveryCountryThrough() {

        // Arrange
        let country = makeCountry(iso2: "FR", name: "France")

        // Act & Assert
        #expect(country.matches(searchQuery: "   "))
    }

    @Test
    func test_matches_withAWordThatIsNoName_rejects() {

        // Arrange
        let country = makeCountry(iso2: "FR", iso3: "FRA", name: "France")

        // Act & Assert
        #expect(!country.matches(searchQuery: "Bolivia"))
    }

    // MARK: - Ordering

    @Test
    func test_sortedByDisplayName_ordersByWhatIsOnScreen() {

        // Arrange
        // In English this is Austria, Germany, Switzerland; the German names run the other way.
        let countries = [makeCountry(iso2: "CH", name: "Switzerland"),
                         makeCountry(iso2: "AT", name: "Austria"),
                         makeCountry(iso2: "DE", name: "Germany")]

        // Act
        let sorted = countries.sortedByDisplayName()

        // Assert
        #expect(sorted.map(\.iso2) == ["AT", "DE", "CH"])
    }

    @Test
    func test_sortedByDisplayName_descending_reversesTheOrder() {

        // Arrange
        let countries = [makeCountry(iso2: "CH", name: "Switzerland"),
                         makeCountry(iso2: "AT", name: "Austria")]

        // Act
        let sorted = countries.sortedByDisplayName(ascending: false)

        // Assert
        #expect(sorted.map(\.iso2) == ["CH", "AT"])
    }
}
