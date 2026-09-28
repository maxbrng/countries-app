//
//  MapFocus.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import CoreGraphics
import Foundation

/// Where the map is looking, in terms both renderers can speak.
///
/// The flat map thinks in a normalised centre and a zoom factor; the globe thinks in a
/// coordinate and a camera distance in metres. Neither can read the other's numbers, which is
/// why switching between 2D and 3D used to drop the view back to its opening position. This is
/// the shared currency: a point on the earth and how much of the world is around it.
///
/// - Note: `nonisolated` and `Equatable` so it can sit in ``MapScreenModel`` and be compared
///   before anything is written back.
nonisolated struct MapFocus: Equatable, Sendable {

    // MARK: - Constants

    /// Degrees of longitude in a full turn of the world.
    private static let fullTurnDegrees: Double = 360

    /// Narrowest span that still means something; below this the two renderers disagree about
    /// what is on screen more than the span itself is worth.
    private static let minimumSpanDegrees: Double = 0.5

    /// Camera distance in metres at which MapKit's globe holds the whole world.
    ///
    /// This is a calibration, not optics: the globe's field of view is MapKit's business, so
    /// the conversion is anchored at the one distance the app itself picks for "the whole
    /// globe in frame" and scaled linearly from there. It is accurate where it matters - both
    /// ends of the range - and approximate in between, which is all a restored camera target
    /// needs to be.
    private static let wholeGlobeDistance: Double = 25_000_000

    // MARK: - Properties

    /// Latitude of the point the map is centred on, in degrees.
    let latitude: Double

    /// Longitude of the point the map is centred on, in degrees.
    let longitude: Double

    /// How wide the visible world is, in degrees of longitude. 360 is the whole world.
    let spanDegrees: Double

    // MARK: - Init

    /// Creates a focus, clamping the span into a range both renderers can express.
    ///
    /// - Parameters:
    ///   - latitude: Latitude of the centre, in degrees.
    ///   - longitude: Longitude of the centre, in degrees.
    ///   - spanDegrees: Visible width in degrees of longitude.
    init(latitude: Double, longitude: Double, spanDegrees: Double) {

        self.latitude = latitude
        self.longitude = longitude
        self.spanDegrees = spanDegrees.clamped(Self.minimumSpanDegrees, Self.fullTurnDegrees)
    }

    // MARK: - Flat map

    /// Reads a focus off the flat map's camera.
    ///
    /// - Parameters:
    ///   - camera: The flat camera, holding a normalised centre and a user zoom.
    ///   - viewport: The area the map is drawn into.
    ///   - worldRect: The projected world's rect at zoom 1.
    ///   - fitScale: Scale applied before the user zoom.
    ///   - projection: Projection the normalised centre is expressed in.
    /// - Returns: The same view expressed geographically, or `nil` when the geometry is not
    ///   laid out yet and the numbers would be meaningless.
    static func fromFlatMap(camera: FlatMapCamera,
                            viewport: CGRect,
                            worldRect: CGRect,
                            fitScale: CGFloat,
                            projection: FlatMapProjectionMode) -> MapFocus? {

        let totalScale = fitScale * camera.userZoom

        guard viewport.width > 0, worldRect.width > 0, totalScale > 0 else { return nil }

        let visibleFraction = viewport.width / (worldRect.width * totalScale)
        let coordinate = FlatMapProjection.unprojectToLongitudeLatitude(point: camera.normalizedCenter,
                                                                       mode: projection)

        return MapFocus(latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        spanDegrees: Double(visibleFraction) * Self.fullTurnDegrees)
    }

    /// Turns this focus back into a flat camera.
    ///
    /// - Parameters:
    ///   - viewport: The area the map is drawn into.
    ///   - worldRect: The projected world's rect at zoom 1.
    ///   - fitScale: Scale applied before the user zoom.
    ///   - projection: Projection the resulting centre should be expressed in.
    /// - Returns: Centre and zoom for ``FlatMapCamera``, or `nil` when the geometry is not laid
    ///   out yet.
    func flatCamera(viewport: CGRect,
                    worldRect: CGRect,
                    fitScale: CGFloat,
                    projection: FlatMapProjectionMode)
    -> (normalizedCenter: CGPoint, userZoom: CGFloat)? {

        guard viewport.width > 0, worldRect.width > 0, fitScale > 0 else { return nil }

        let visibleFraction = CGFloat(spanDegrees / Self.fullTurnDegrees)

        guard visibleFraction > 0 else { return nil }

        let totalScale = viewport.width / (worldRect.width * visibleFraction)
        let center = FlatMapProjection.projectLongitudeLatitude(longitude: longitude,
                                                                latitude: latitude,
                                                                mode: projection)

        return (center, totalScale / fitScale)
    }

    // MARK: - Globe

    /// Reads a focus off the globe's camera.
    ///
    /// - Parameters:
    ///   - latitude: Latitude the camera is over, in degrees.
    ///   - longitude: Longitude the camera is over, in degrees.
    ///   - distance: Camera distance in metres.
    /// - Returns: The same view expressed as a span.
    static func fromGlobe(latitude: Double, longitude: Double, distance: Double) -> MapFocus {

        MapFocus(latitude: latitude,
                 longitude: longitude,
                 spanDegrees: distance / Self.wholeGlobeDistance * Self.fullTurnDegrees)
    }

    /// Camera distance in metres that puts this focus's span on the globe.
    var globeDistance: Double {
        spanDegrees / Self.fullTurnDegrees * Self.wholeGlobeDistance
    }
}
