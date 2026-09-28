//
//  GlobeMapView.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import SwiftUI
import MapKit
import SwiftData

/// 3D globe renderer behind ``MapAppearance``, built on MapKit's hybrid map style.
///
/// Country geometry comes from ``GlobeShapeCache`` via ``GlobeMapViewModel`` and is drawn as
/// `MapPolygon` overlays on top of MapKit's own borders. Only marked and selected countries are
/// overlaid, and selecting one flies the camera to it.
///
/// - Note: Selection is mirrored into the local `selectedISO2` state in lowercase, because the
///   globe geometry is keyed by lowercased iso2 while ``Country`` stores it uppercase.
struct GlobeMapView: View {

    // MARK: - Constants

    /// Camera framing constants for the initial view and the focus heuristic.
    private enum Camera {

        /// Latitude the globe opens at, biased north so most landmass is visible.
        static let initialLatitude: CLLocationDegrees = 20
        /// Longitude the globe opens at (prime meridian).
        static let initialLongitude: CLLocationDegrees = 0
        /// Opening camera distance in metres: the whole globe in frame.
        static let initialDistance: CLLocationDistance = 25_000_000

        /// Divisor in metres that normalises a country diagonal before the log is taken,
        /// so one log unit corresponds to a country roughly ten times wider.
        static let diagonalScaleReference: Double = 100_000
        /// Smallest multiple of the diagonal the camera stays back at, for tiny countries.
        static let baseDistanceFactor: Double = 1.05
        /// Extra distance factor added per log unit of country size.
        static let distanceFactorPerScaleUnit: Double = 0.42
        /// Closest the camera may get, in metres: keeps city-state overlays readable.
        static let minimumDistance: Double = 2_800_000
        /// Farthest the camera may pull back to, in metres, for continent-sized countries.
        static let maximumDistance: Double = 20_000_000

        /// Spring response of the fly-to animation, in seconds.
        static let focusAnimationResponse: Double = 2.5
        /// Spring damping of the fly-to animation; 1.0 means no overshoot.
        static let focusAnimationDamping: Double = 1.0
    }

    /// Overlay and loading-indicator styling.
    private enum Style {

        /// Stroke width of the selected country's outline.
        static let selectedStrokeWidth: CGFloat = 1.8
        /// Stroke width of every other highlighted country.
        ///
        /// Thinner than it was. Over photography a heavy line is what reads as scribble; the
        /// casing underneath is what makes a thin line legible, not the weight.
        static let strokeWidth: CGFloat = 0.8

        /// How much wider the dark casing is than the line it sits behind, in points.
        ///
        /// The casing has to show on both sides of the light line, so this is added to the
        /// width and half of it ends up visible on each side.
        static let casingWidthAddition: CGFloat = 2

        /// Opacity of the dark casing under the outline.
        ///
        /// Dark enough to separate the light line from bright desert, translucent enough that
        /// the imagery still reads through it over the sea.
        static let casingOpacity: Double = 0.55

        /// Outline opacity of unselected countries; the selected one is drawn fully opaque.
        static let unselectedStrokeOpacity: Double = 0.85

        static let visitedSelectedFillOpacity: Double = 0.55
        static let visitedFillOpacity: Double = 0.4
        static let wishlistSelectedFillOpacity: Double = 0.6
        static let wishlistFillOpacity: Double = 0.45
        static let neutralSelectedFillOpacity: Double = 0.35
        static let neutralFillOpacity: Double = 0.15

    }

    // MARK: - State

    @Query private var countries: [Country]
    @Binding private var selectedCountry: Country?

    /// Where the map is looking, shared with the flat map so a switch between the two keeps it.
    @Binding private var sharedFocus: MapFocus?

    @State private var viewModel = GlobeMapViewModel()
    @State private var selectedISO2: String?

    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: .init(latitude: Camera.initialLatitude,
                                    longitude: Camera.initialLongitude),
            distance: Camera.initialDistance
        )
    )

    // MARK: - Init

    /// Creates the globe view.
    ///
    /// - Parameters:
    ///   - selectedCountry: Shared selection binding, kept in sync in both directions:
    ///     an external change focuses the camera, a tap on the globe writes back into it.
    ///   - sharedFocus: Where the map is looking, shared with the flat map. Read once when the
    ///     globe appears and written as the camera settles. Defaults to a constant `nil` for
    ///     previews, which have nothing to restore and nothing to report.
    init(selectedCountry: Binding<Country?>,
         sharedFocus: Binding<MapFocus?> = .constant(nil)) {

        self._selectedCountry = selectedCountry
        self._sharedFocus = sharedFocus
        _countries = Query()
    }

    // MARK: - Derived data

    /// Only marked and selected countries get an overlay. MapKit already draws
    /// every border in hybrid style, so painting all ~240 countries would cost a
    /// lot of rendering for no visual gain.
    private var highlightedShapes: [GlobeCountryShape] {

        guard !viewModel.shapes.isEmpty else { return [] }

        let marked = Set(
            countries
                .filter { $0.status != .none }
                .map { $0.iso2.lowercased() }
        )

        guard !marked.isEmpty || selectedISO2 != nil else { return [] }

        return viewModel.shapes.filter { shape in
            marked.contains(shape.iso2) || shape.iso2 == selectedISO2
        }
    }

    // MARK: - Body

    /// Hybrid MapKit map with the highlight overlays and the loading indicator on top.
    var body: some View {

        MapReader { proxy in

            ZStack {

                Map(position: $cameraPosition) {

                    // The casing pass first, for every country, so that a neighbouring
                    // country's light outline can never be drawn over another's dark one.
                    ForEach(highlightedShapes) { shape in

                        let width = strokeWidth(isSelected: selectedISO2 == shape.iso2)

                        ForEach(Array(shape.polygons.enumerated()), id: \.offset) { _, polygon in
                            MapPolygon(coordinates: polygon.coordinates)
                                .foregroundStyle(.clear)
                                .stroke(MapPalette.Globe.outlineCasing
                                            .opacity(Style.casingOpacity),
                                        lineWidth: width + Style.casingWidthAddition)
                        }
                    }

                    ForEach(highlightedShapes) { shape in

                        let isSelected = selectedISO2 == shape.iso2
                        let fill = fillColor(for: shape.iso2, isSelected: isSelected)
                        let width = strokeWidth(isSelected: isSelected)

                        ForEach(Array(shape.polygons.enumerated()), id: \.offset) { _, polygon in
                            MapPolygon(coordinates: polygon.coordinates)
                                .foregroundStyle(fill)
                                .stroke(isSelected
                                            ? MapPalette.Globe.outline
                                            : MapPalette.Globe.outline
                                                .opacity(Style.unselectedStrokeOpacity),
                                        lineWidth: width)
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .onTapGesture { point in
                    handleTap(at: point, mapProxy: proxy)
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                // `.onEnd` on purpose: the globe reports a camera on every frame of a drag,
                // and the shared focus only needs where the user stopped.
                .onMapCameraChange(frequency: .onEnd) { context in
                    publishSharedFocus(camera: context.camera)
                }

                LoadStateOverlay(state: viewModel.loadState,
                                 loadingMessage: "Building the globe…",
                                 failureMessage: Self.failureMessage) {
                    Task { await viewModel.reloadShapes() }
                }
            }
        }
        .task {
            viewModel.updateCountryIndex(countries: countries)
            await viewModel.loadShapesIfNeeded()
            restoreSharedFocus()
            syncSelectionFromBinding()
        }
        .onChange(of: countries) { _, newCountries in
            // Status changes only affect colouring, never the geometry.
            viewModel.updateCountryIndex(countries: newCountries)
        }
        .onChange(of: selectedCountry) { _, _ in
            syncSelectionFromBinding()
        }
    }

    // MARK: - Shared focus

    /// Moves the camera to where the flat map left off, once, when the globe appears.
    ///
    /// Runs before ``syncSelectionFromBinding()``, so a selection that arrives with the switch
    /// still gets the last word and flies the camera to its country.
    private func restoreSharedFocus() {

        guard let sharedFocus else { return }

        cameraPosition = .camera(
            MapCamera(centerCoordinate: .init(latitude: sharedFocus.latitude,
                                              longitude: sharedFocus.longitude),
                      distance: sharedFocus.globeDistance)
        )
    }

    /// Reports the camera into the shared focus so the flat map can pick it up.
    ///
    /// - Parameter camera: The camera the globe settled on.
    private func publishSharedFocus(camera: MapCamera) {

        sharedFocus = MapFocus.fromGlobe(latitude: camera.centerCoordinate.latitude,
                                         longitude: camera.centerCoordinate.longitude,
                                         distance: camera.distance)
    }

    // MARK: - Selection

    /// Mirrors the external ``selectedCountry`` binding into the local iso2 selection and
    /// focuses the camera when the selection actually changed.
    private func syncSelectionFromBinding() {

        guard let selectedCountry else {
            selectedISO2 = nil
            return
        }

        let iso2 = selectedCountry.iso2.lowercased()
        guard iso2 != selectedISO2 else { return }

        selectedISO2 = iso2
        focusCountry(iso2: iso2)
    }

    /// Resolves a tap into a country selection: a miss clears the selection, a tap on the
    /// already selected country deselects it, anything else selects and focuses.
    ///
    /// - Parameters:
    ///   - point: Tap location in the map view's local coordinate space.
    ///   - mapProxy: Proxy used to convert the point into a coordinate.
    private func handleTap(at point: CGPoint, mapProxy: MapProxy) {

        guard let coordinate = mapProxy.convert(point, from: .local) else { return }

        guard let shape = viewModel.country(at: coordinate) else {
            selectedISO2 = nil
            selectedCountry = nil
            return
        }

        if selectedISO2 == shape.iso2 {
            selectedISO2 = nil
            selectedCountry = nil
            return
        }

        selectedISO2 = shape.iso2
        selectedCountry = viewModel.countryIndex.countriesByISO2[shape.iso2]
        focusCountry(iso2: shape.iso2)
    }

    // MARK: - Camera

    /// Flies the camera to a country, deriving the viewing distance from the country's size.
    ///
    /// The distance is the mainland bounding-box diagonal multiplied by a factor that grows
    /// logarithmically with that diagonal: small countries are framed only slightly wider than
    /// their own extent, while large ones need proportionally more room, and the result is
    /// clamped so neither city states nor continents end up outside a usable range.
    ///
    /// - Parameter iso2: Lowercased iso2 code of the country to frame; unknown codes are ignored.
    /// - Note: Does nothing until the shapes have finished loading.
    private func focusCountry(iso2: String) {

        guard let shape = viewModel.shapes.first(where: { $0.iso2 == iso2 }) else { return }

        let width = shape.focusRect.size.width
        let height = shape.focusRect.size.height
        let diagonal = (width * width + height * height).squareRoot()

        // The + 1 keeps the logarithm defined and non-negative for diagonals below the reference.
        let scaleLog = log10(diagonal / Camera.diagonalScaleReference + 1)
        let dynamicFactor = Camera.baseDistanceFactor + (scaleLog * Camera.distanceFactorPerScaleUnit)
        let distance = (diagonal * dynamicFactor).clamped(Camera.minimumDistance,
                                                          Camera.maximumDistance)

        withAnimation(.spring(response: Camera.focusAnimationResponse,
                              dampingFraction: Camera.focusAnimationDamping)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: shape.center, distance: distance))
        }
    }

    // MARK: - Styling

    /// Overlay fill for a country, derived from its ``CountryStatus``.
    ///
    /// - Parameters:
    ///   - iso2: Lowercased iso2 code of the country to colour.
    ///   - isSelected: Whether this country is currently selected; selected fills are stronger.
    /// - Returns: The fill colour, or a neutral translucent white for countries that are not
    ///   present in the index.
    private func fillColor(for iso2: String, isSelected: Bool) -> Color {

        guard let country = viewModel.countryIndex.countriesByISO2[iso2] else {
            return MapPalette.Globe.neutralFill.opacity(Style.neutralFillOpacity)
        }

        switch country.status {
        case .visited:
            return MapPalette.Globe.visitedFill.opacity(isSelected
                                                            ? Style.visitedSelectedFillOpacity
                                                            : Style.visitedFillOpacity)
        case .wishlist:
            return MapPalette.Globe.wishlistFill.opacity(isSelected
                                                            ? Style.wishlistSelectedFillOpacity
                                                            : Style.wishlistFillOpacity)
        case .none:
            return MapPalette.Globe.neutralFill.opacity(isSelected
                                                            ? Style.neutralSelectedFillOpacity
                                                            : Style.neutralFillOpacity)
        }
    }

    /// Outline width for one country.
    ///
    /// - Parameter isSelected: Whether the country is the selected one.
    /// - Returns: The stroke width in points, before the casing addition.
    private func strokeWidth(isSelected: Bool) -> CGFloat {
        isSelected ? Style.selectedStrokeWidth : Style.strokeWidth
    }

    /// Shown when the overlays cannot be built.
    ///
    /// Names what is missing rather than what failed: without the overlays the globe still
    /// works as a globe, it just has no countries on it.
    private static let failureMessage: LocalizedStringKey =
        "The country outlines could not be built. The globe itself still works."
}
