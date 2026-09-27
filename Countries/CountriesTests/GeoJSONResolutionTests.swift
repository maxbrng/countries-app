//
//  GeoJSONResolutionTests.swift
//  CountriesTests
//
//  Created by Max Breuning on 27.09.26.
//

import Testing
@testable import Countries

/// Covers how a GeoJSON feature is matched to a seeded country.
///
/// Every value here is lowercased, because ``GeoJSONLoader`` lowercases the raw property
/// before it resolves. The index is built by hand: the point of these tests is the matching
/// rules, not the bundled file.
struct GeoJSONResolutionTests {

    // MARK: - Fixture

    /// A lookup table with one country reachable by ISO3 and by name.
    private static let resolver = GeoJSONLoader.ResolverIndex(
        iso3ToIso2: ["deu": "de", "twn": "tw"],
        nameToIso2: ["germany": "de", "taiwan": "tw", "france": "fr"]
    )

    // MARK: - Tests

    @Test func test_resolveISO2_twoLetterCode_returnsItUnchanged() {

        let resolved = GeoJSONLoader.resolveISO2(rawISO: "de",
                                                 rawName: "germany",
                                                 resolver: Self.resolver)

        #expect(resolved == "de")
    }

    @Test func test_resolveISO2_threeLetterCode_mapsThroughTheIndex() {

        let resolved = GeoJSONLoader.resolveISO2(rawISO: "deu",
                                                 rawName: nil,
                                                 resolver: Self.resolver)

        #expect(resolved == "de")
    }

    @Test func test_resolveISO2_unknownThreeLetterCode_fallsBackToTheName() {

        let resolved = GeoJSONLoader.resolveISO2(rawISO: "xxx",
                                                 rawName: "france",
                                                 resolver: Self.resolver)

        #expect(resolved == "fr")
    }

    @Test func test_resolveISO2_missingCodePlaceholder_usesTheName() {

        // Natural Earth writes "-99" where it has no code: France and Norway carry it.
        let resolved = GeoJSONLoader.resolveISO2(rawISO: "-99",
                                                 rawName: "france",
                                                 resolver: Self.resolver)

        #expect(resolved == "fr")
    }

    @Test func test_resolveISO2_codeOfUnusableLength_usesTheName() {

        // Taiwan is "CN-TW" in Natural Earth. Returning nil on that is what used to keep
        // Taiwan off the map entirely.
        let resolved = GeoJSONLoader.resolveISO2(rawISO: "cn-tw",
                                                 rawName: "taiwan",
                                                 resolver: Self.resolver)

        #expect(resolved == "tw")
    }

    @Test func test_resolveISO2_nothingMatches_returnsNil() {

        let resolved = GeoJSONLoader.resolveISO2(rawISO: "cn-tw",
                                                 rawName: "somaliland",
                                                 resolver: Self.resolver)

        #expect(resolved == nil)
    }

    @Test func test_resolveISO2_noCodeAndNoName_returnsNil() {

        let resolved = GeoJSONLoader.resolveISO2(rawISO: nil,
                                                 rawName: nil,
                                                 resolver: Self.resolver)

        #expect(resolved == nil)
    }
}
