//
//  FlatMapShapeCache.swift
//  Countries
//
//  Created by Max Breuning on 24.01.26.
//

import Foundation

actor FlatMapShapeCache {

    static let shared = FlatMapShapeCache()

    enum Variant: Hashable, Sendable {
        case full     // interactive map
        case light    // preview map
    }

    private struct Key: Hashable {
        let projection: FlatMapProjectionMode
        let variant: Variant
    }

    private var cache: [Key: [RenderCountryShape]] = [:]
    private var inFlight: [Key: Task<[RenderCountryShape], Error>] = [:]

    func shapes(
        projectionMode: FlatMapProjectionMode,
        resolver: GeoJSONLoader.ResolverIndex,
        variant: Variant
    ) async throws -> [RenderCountryShape] {

        let key = Key(projection: projectionMode, variant: variant)

        if let cached = cache[key] { return cached }
        if let inflight = inFlight[key] { return try await inflight.value }

        let task = Task.detached(priority: .userInitiated) { () async throws -> [RenderCountryShape] in
            let resolved = try await GeoJSONLoader.loadResolvedFeatures(
                resolver: resolver,
                keySet: .init()
            )

            let builderVariant: FlatPathBuilder.Variant = (variant == .full ? .full : .light)

            var built: [RenderCountryShape] = []
            built.reserveCapacity(resolved.count)

            for feature in resolved {
                let result = FlatPathBuilder.build(
                    from: feature.geometry,
                    projectionMode: projectionMode,
                    iso2: feature.iso2,
                    variant: builderVariant
                )

                built.append(
                    RenderCountryShape(
                        id: feature.iso2,
                        iso2: feature.iso2,
                        path: result.path,
                        labelAnchor: result.labelAnchor,
                        focusBoundingBoxNormalized: result.focusBoundingBox
                    )
                )
            }
            return built
        }

        inFlight[key] = task
        do {
            let shapes = try await task.value
            cache[key] = shapes
            inFlight[key] = nil
            return shapes
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func clearAll() {
        cache.removeAll()
        inFlight.removeAll()
    }
}
