//
//  MapScreenRouteTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 28.09.26.
//

import SwiftData
import Testing
@testable import Countries

/// Covers how the map's selection and its sheet route move together.
///
/// The two used to be one value - ``MapScreenModel/selectedCountry`` read straight off
/// ``MapScreenModel/route`` - which meant anything else that took the sheet deselected the
/// country first. Opening the appearance panel to switch to 3D did exactly that, so the globe
/// always came up on nothing. They are separate values now, and these tests pin down which
/// transitions clear the selection and which do not.
@MainActor
struct MapScreenRouteTests {

    // MARK: - Fixture

    /// A country that exists only for the length of one test.
    private func makeCountry(iso2: String, name: String) throws -> Country {

        let schema = Schema(versionedSchema: CountriesSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: configuration))

        let country = Country(iso2: iso2,
                              nameEnglish: name,
                              status: .none,
                              isUNMember: true,
                              dataHasSourceTranslation: false,
                              travelTags: [],
                              climateTags: [],
                              costLevel: .medium,
                              safetyLevel: .safe,
                              translations: [:])
        context.insert(country)
        try context.save()

        return country
    }

    // MARK: - Selecting

    @Test func test_selectingACountry_opensItsSheet() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")

        // Act
        model.selectedCountry = country

        // Assert
        #expect(model.route == .country(country))
    }

    @Test func test_routingToACountry_selectsIt() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")

        // Act
        model.route = .country(country)

        // Assert
        #expect(model.selectedCountry === country)
    }

    // MARK: - Leaving a country's sheet

    @Test func test_openingTheAppearancePanel_keepsTheSelection() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")
        model.selectedCountry = country

        // Act
        model.showAppearancePanel = true

        // Assert: this is what lets a switch to 3D arrive with a country still chosen.
        #expect(model.route == .appearance)
        #expect(model.selectedCountry === country)
    }

    @Test func test_closingTheCountrySheet_clearsTheSelection() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")
        model.selectedCountry = country

        // Act: what the sheet's close button and a swipe-away both do.
        model.route = .none

        // Assert
        #expect(model.selectedCountry == nil)
    }

    @Test func test_closingTheAppearancePanel_leavesTheSelectionAlone() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")
        model.selectedCountry = country
        model.showAppearancePanel = true

        // Act
        model.showAppearancePanel = false

        // Assert: nothing about the appearance panel is a statement about the country.
        #expect(model.route == .none)
        #expect(model.selectedCountry === country)
    }

    @Test func test_deselecting_closesTheCountrySheet() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")
        model.selectedCountry = country

        // Act
        model.selectedCountry = nil

        // Assert
        #expect(model.route == .none)
    }

    @Test func test_deselecting_whileTheAppearancePanelIsUp_leavesItUp() throws {

        // Arrange
        let model = MapScreenModel()
        let country = try makeCountry(iso2: "DZ", name: "Algeria")
        model.selectedCountry = country
        model.showAppearancePanel = true

        // Act
        model.selectedCountry = nil

        // Assert: the panel the user opened is not the map's to close.
        #expect(model.route == .appearance)
    }

    @Test func test_selectingAnotherCountry_swapsTheSheet() throws {

        // Arrange
        let model = MapScreenModel()
        let algeria = try makeCountry(iso2: "DZ", name: "Algeria")
        let libya = try makeCountry(iso2: "LY", name: "Libya")
        model.selectedCountry = algeria

        // Act
        model.selectedCountry = libya

        // Assert
        #expect(model.route == .country(libya))
        #expect(model.selectedCountry === libya)
    }
}
