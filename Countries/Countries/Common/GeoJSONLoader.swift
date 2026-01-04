//
//  GeoJSONLoader.swift
//  Countries
//
//  Created by Max Breuning on 04.01.26.
//

import MapKit

final class CountryOverlay: MKPolygon {
    let isoCode: String

    init(coordinates: [CLLocationCoordinate2D], isoCode: String) {
        self.isoCode = isoCode.lowercased()
        super.init(coordinates: coordinates, count: coordinates.count)
    }
}

final class GeoJSONLoader {

    static func load(from resource: String) throws -> [CountryOverlay] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        let objects = try MKGeoJSONDecoder().decode(data)

        var overlays: [CountryOverlay] = []

        for case let feature as MKGeoJSONFeature in objects {
            guard
                let propsData = feature.properties,
                let props = try? JSONSerialization.jsonObject(with: propsData) as? [String: Any],
                let iso = (props["ISO_A2"] ?? props["ISO_A3"]) as? String,
                iso.count >= 2
            else { continue }

            for geo in feature.geometry {
                if let p = geo as? MKPolygon {
                    overlays.append(CountryOverlay(
                        coordinates: p.coordinates(),
                        isoCode: iso
                    ))
                } else if let mp = geo as? MKMultiPolygon {
                    for p in mp.polygons {
                        overlays.append(CountryOverlay(
                            coordinates: p.coordinates(),
                            isoCode: iso
                        ))
                    }
                }
            }
        }

        return overlays
    }
}

private extension MKPolygon {
    func coordinates() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
