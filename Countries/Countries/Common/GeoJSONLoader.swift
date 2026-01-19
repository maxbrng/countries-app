import Foundation

/// Shared loader that decodes GeoJSON from the app bundle and resolves each feature to an ISO2 code.
/// The resulting `ResolvedFeature` can be used by different renderers (Flat / Globe) without duplicating decoding code.
enum GeoJSONLoader {

    struct ResolvedFeature: Sendable {
        let iso2: String
        let geometry: GeoJSON.Geometry
        let properties: [String: JSONValue]
    }

    struct KeySet: Sendable {
        let isoKeys: [String]
        let nameKeys: [String]

        init(
            isoKeys: [String] = ["ISO_A2", "iso_a2", "ISO2", "POSTAL", "ISO_A3", "iso_a3", "ADM0_A3"],
            nameKeys: [String] = ["admin", "name", "ADMIN", "NAME", "name_en", "NAME_EN"]
        ) {
            self.isoKeys = isoKeys
            self.nameKeys = nameKeys
        }
    }

    static func loadResolvedFeatures(
        resource: String = "countries",
        index: CountryIndex,
        keySet: KeySet
    ) async throws -> [ResolvedFeature] {
        
        let data = try await loadResourceData(resource: resource,
                                              fileExtension: "geojson")
        
        let collection = try JSONDecoder().decode(GeoJSON.FeatureCollection.self, from: data)

        var resolved: [ResolvedFeature] = []
        resolved.reserveCapacity(collection.features.count)

        for feature in collection.features {
            
            let props = feature.properties ?? [:]

            let rawISO = props.firstString(for: keySet.isoKeys)?.lowercased()
            let rawName = props.firstString(for: keySet.nameKeys)?.lowercased()

            let iso2 = resolveISO2(rawISO: rawISO, rawName: rawName, index: index)
            guard let iso2, iso2.count == 2 else { continue }

            resolved.append(.init(iso2: iso2, geometry: feature.geometry, properties: props))
        }

        return resolved
    }

    // MARK: - Private

    private static func loadResourceData(resource: String, fileExtension: String) async throws -> Data {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            throw CocoaError(.fileNoSuchFile)
        }

        // Keep file IO off the main actor.
        return try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    private static func resolveISO2(rawISO: String?, rawName: String?, index: CountryIndex) -> String? {
        guard let rawISO, rawISO != "-99" else {
            if let rawName { return index.nameToIso2[rawName] }
            return nil
        }

        switch rawISO.count {
        case 2:
            return rawISO
        case 3:
            return index.iso3ToIso2[rawISO]
        default:
            return nil
        }
    }
}

// MARK: - GeoJSONModels

enum GeoJSON {
    struct FeatureCollection: Decodable, Sendable {
        let type: String
        let features: [Feature]
    }
    
    struct Feature: Decodable, Sendable {
        let type: String
        let properties: [String: JSONValue]?
        let geometry: Geometry
    }
    
    enum Geometry: Decodable, Sendable {
        case polygon([[[Double]]])
        case multiPolygon([[[[Double]]]])
        
        private enum CodingKeys: String, CodingKey { case type, coordinates }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            switch type {
            case "Polygon":
                self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon":
                self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
            default:
                self = .polygon([])
            }
        }
    }
}

enum JSONValue: Decodable, Sendable {
    
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() { self = .null; return }
            if let string = try? container.decode(String.self) { self = .string(string); return }
            if let number = try? container.decode(Double.self) { self = .number(number); return }
            if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
            if let object = try? container.decode([String: JSONValue].self) { self = .object(object); return }
            if let array = try? container.decode([JSONValue].self) { self = .array(array); return }
        }
        self = .null
    }
    
    var stringValue: String? {
        
        switch self {
        case .string(let string):
            return string
            
        case .number(let number):
            if number.rounded() == number { return String(Int(number)) }
            return String(number)
            
        case .bool(let bool):
            return bool ? "true" : "false"
            
        default:
            return nil
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Returns the first non-empty string value for any of the keys, case-insensitive.
    func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue?.trimmedNonEmpty { return value }
        }
        
        let lowerKeys = Set(keys.map { $0.lowercased() })
        for (key, value) in self where lowerKeys.contains(key.lowercased()) {
            if let value = value.stringValue?.trimmedNonEmpty { return value }
        }
        return nil
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
