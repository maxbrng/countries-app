import MapKit
import Foundation

/// A loader class to decode country overlays from a GeoJSON file asynchronously.
///
/// Usage:
/// 1. Import your GeoJSON file (e.g. "countries.geojson") into your Xcode project:
///    - Drag the file into your project navigator.
///    - Ensure "Copy items if needed" is checked.
///    - Verify the file is added to your app target under "Target Membership".
/// 2. Use `GeoJSONLoader.loadCountryOverlays()` to load polygons asynchronously.
///
/// If your GeoJSON file uses different property keys for ISO codes,
/// adjust the `isoPropertyKeys` parameter accordingly.
///
/// If your file is inside a folder reference named "Resources":
/// pass `subdirectory: "Resources"`.
///
/// If your file is part of a Swift Package:
/// pass `in: .module` (from the package's context) or rely on automatic fallback.
public final class GeoJSONLoader {
    
    /// Loads country overlays from a GeoJSON file in the specified bundle and subdirectory.
    ///
    /// - Parameters:
    ///   - resource: The name of the GeoJSON file resource (without extension).
    ///   - ext: The file extension, default is "geojson".
    ///   - bundle: The bundle to search for the resource, default is `.main`.
    ///   - subdirectory: Optional subdirectory within the bundle to look for the resource.
    ///   - isoPropertyKeys: Array of property keys to look for ISO codes, in order of priority.
    /// - Returns: An array of `MKPolygon` objects with their `title` set to the ISO code.
    /// - Throws: Errors related to file not found, data reading, or decoding failures.
    public static func loadCountryOverlays(
        fromResource resource: String = "countries",
        withExtension ext: String = "geojson",
        in bundle: Bundle = .main,
        subdirectory: String? = nil,
        isoPropertyKeys: [String] = ["ISO_A2", "ISO_A3", "iso_a2", "iso_a3", "COUNTRY", "ADMIN", "name"]
    ) async throws -> [MKPolygon] {
        guard let url = resolveResourceURL(named: resource, ext: ext, in: bundle, subdirectory: subdirectory) else {
            throw NSError(domain: "GeoJSONLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Resource '\(resource).\(ext)' not found in bundle \(bundle.bundlePath). Set target membership, or pass the correct bundle/subdirectory."])
        }

        let data = try Data(contentsOf: url)
        let decoder = MKGeoJSONDecoder()
        let geoJSONObjects = try decoder.decode(data)

        var overlays: [MKPolygon] = []

        for object in geoJSONObjects {
            guard let feature = object as? MKGeoJSONFeature,
                  let propertiesData = feature.properties,
                  let isoCode = isoCode(from: propertiesData, keys: isoPropertyKeys) else {
                // Skip feature if no ISO code found or not a feature
                continue
            }

            for geometry in feature.geometry {
                if let polygon = geometry as? MKPolygon {
                    polygon.title = isoCode
                    overlays.append(polygon)
                } else if let multiPolygon = geometry as? MKMultiPolygon {
                    for subPolygon in multiPolygon.polygons {
                        subPolygon.title = isoCode
                        overlays.append(subPolygon)
                    }
                }
            }
        }

        return overlays
    }
    
    /// Parses the ISO code from GeoJSON properties data using specified keys.
    ///
    /// The search tries exact case-sensitive matches first,
    /// then tries case-insensitive matches.
    /// The first non-empty string found is returned, trimmed of whitespace.
    ///
    /// - Parameters:
    ///   - propertiesData: JSON data representing the feature properties.
    ///   - keys: The list of keys to search for the ISO code.
    /// - Returns: The first matching ISO code string, or `nil` if none found.
    private static func isoCode(from propertiesData: Data, keys: [String]) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: propertiesData, options: []),
              let dict = jsonObject as? [String: Any] else {
            return nil
        }
        
        // Search case-sensitive keys first
        for key in keys {
            if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Search case-insensitive keys
        let lowercasedKeys = keys.map { $0.lowercased() }
        for (dictKey, value) in dict {
            if lowercasedKeys.contains(dictKey.lowercased()),
               let stringValue = value as? String,
               !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    /// Attempts to resolve a resource URL across the provided bundle, main bundle, Swift Package bundle, and all bundles/frameworks.
    private static func resolveResourceURL(named name: String, ext: String, in bundle: Bundle, subdirectory: String?) -> URL? {
        // Try the provided bundle with optional subdirectory
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext) { return url }

        // Main bundle fallback
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }

        // Swift Package resources (if applicable)
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext) { return url }
        #endif

        // Search all known bundles
        let candidates = Array(Set(Bundle.allBundles + Bundle.allFrameworks))
        for b in candidates {
            if let url = b.url(forResource: name, withExtension: ext, subdirectory: subdirectory) { return url }
            if let url = b.url(forResource: name, withExtension: ext) { return url }
            if let url = deepSearch(resourceNamed: "\(name).\(ext)", in: b) { return url }
        }

        // Deep search the provided bundle as a last resort
        if let url = deepSearch(resourceNamed: "\(name).\(ext)", in: bundle) { return url }

        return nil
    }

    /// Recursively searches the bundle's resource directory for a file with the given name.
    private static func deepSearch(resourceNamed fileName: String, in bundle: Bundle) -> URL? {
        guard let root = bundle.resourceURL else { return nil }
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == fileName.lowercased() {
                    return fileURL
                }
            }
        }
        return nil
    }
}
