import SwiftUI
import MapKit

struct FullMapScreen: View {
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CountriesViewModel
    @State private var initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    
    var body: some View {
        NavigationStack {
            CountryMapView(
                states: $viewModel.states,
                selectedCountry: viewModel.selectedCountry,
                isInteractive: true,
                onTapCountry: { iso in
                    viewModel.toggleSelection(for: iso)
                },
                initialRegion: initialRegion,
                resourceName: "countries",
                resourceExtension: "geojson",
                resourceSubdirectory: "resources/assets"
                // If stored under a subdirectory in the bundle, also pass:
                // , resourceSubdirectory: "Resources"
            )
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let selected = viewModel.selectedCountry {
                        Button("Mark as visited") {
                            viewModel.markVisited(for: selected)
                        }
                    }
                }
            }
            .navigationTitle("World Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    FullMapScreen(viewModel: CountriesViewModel())
}
