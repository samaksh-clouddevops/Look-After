import SwiftUI
import MapKit
import LookAfterCore
import LookAfterFeatures

/// Map-based coordinate picker for saving "Home"/"Office" locations in Settings.
/// Uses only MapKit + `NSLocationWhenInUseUsageDescription` — no paid entitlement required.
struct LocationPickerSheet: View {
    let title: String
    let initialCoordinate: CLLocationCoordinate2D?
    /// When true, shows an editable "Place name" field (for custom places like "Gym").
    var showsNameField: Bool = false
    var initialName: String = ""
    let onSave: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var pinCoordinate: CLLocationCoordinate2D
    @State private var customName: String
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isLocatingCurrent = false
    private let locationCaptureService = LocationCaptureService()

    init(
        title: String,
        initialCoordinate: CLLocationCoordinate2D?,
        showsNameField: Bool = false,
        initialName: String = "",
        onSave: @escaping (String, CLLocationCoordinate2D) -> Void
    ) {
        self.title = title
        self.initialCoordinate = initialCoordinate
        self.showsNameField = showsNameField
        self.initialName = initialName
        self.onSave = onSave
        let start = initialCoordinate ?? CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
        _pinCoordinate = State(initialValue: start)
        _customName = State(initialValue: initialName)
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(center: start, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        ))
    }

    private var trimmedName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !showsNameField || !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        Annotation(title, coordinate: pinCoordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.red)
                        }
                    }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            pinCoordinate = coordinate
                        }
                    }
                }

                VStack {
                    if showsNameField {
                        nameField
                    }
                    searchBar
                    Spacer()
                    currentLocationButton
                }
                .padding()
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, pinCoordinate)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var nameField: some View {
        TextField("Place name (e.g. Gym)", text: $customName)
            .textFieldStyle(.roundedBorder)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Search for an address", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await searchAddress() } }
                Button(action: { Task { await searchAddress() } }) {
                    if isSearching {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var currentLocationButton: some View {
        Button(action: { Task { await useCurrentLocation() } }) {
            HStack {
                if isLocatingCurrent {
                    ProgressView()
                } else {
                    Image(systemName: "location.fill")
                }
                Text("Use current location")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
        .disabled(isLocatingCurrent)
    }

    private func searchAddress() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate else {
                searchError = "No results found."
                return
            }
            pinCoordinate = coordinate
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            )
        } catch {
            searchError = "Search failed: \(error.localizedDescription)"
        }
    }

    private func useCurrentLocation() async {
        isLocatingCurrent = true
        defer { isLocatingCurrent = false }
        do {
            let coordinate = try await locationCaptureService.currentCoordinate()
            pinCoordinate = coordinate
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            )
        } catch {
            searchError = "Couldn't get current location: \(error.localizedDescription)"
        }
    }
}
