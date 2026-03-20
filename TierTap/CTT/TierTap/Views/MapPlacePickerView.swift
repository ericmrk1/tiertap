import SwiftUI
import MapKit
import CoreLocation

/// Map + local search for any place (trip city, hotel, home, airports, etc.).
struct MapPlacePickerView: View {
    var navigationTitle: String = "Choose place"
    /// Default natural-language query when searching near a region (e.g. "hotel", "casino").
    var defaultLandmarkQuery: String = "point of interest"
    /// Shows "Current location" to recenter the map and refresh nearby search (e.g. trip primary location).
    var showsCurrentLocationButton: Bool = false
    /// When true (e.g. flight endpoints), 3-letter IATA and 4-letter ICAO-style input is expanded (e.g. `LAX` → `LAX airport`) for geocoding and local search, with a broad map fallback if geocoding fails.
    var allowsAirportCodeSearch: Bool = false
    /// When true (flight legs), a chosen pin uses **IATA or ICAO** (`AirportPicklistEntry.storageCode`) for `name` when it matches `AirportCatalog`.
    var preferIataAirportCode: Bool = false
    @Binding var name: String
    @Binding var subtitle: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsStore: SettingsStore

    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.1147, longitude: -115.1728),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
    @State private var searchResults: [NearbyCasino] = []
    @State private var isSearching = false
    @State private var hasLocatedOnce = false
    @State private var searchError: String?
    @State private var addressQuery: String = ""
    @State private var manualName: String = ""
    @State private var manualSubtitle: String = ""
    @State private var pendingManualRecenter = false

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mapSection
                        manualSection
                        resultsSection
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .onAppear {
                locationManager.requestWhenInUse()
                manualName = name
                manualSubtitle = subtitle
            }
            .onChange(of: locationManager.lastLocation) { _ in
                handleLocationUpdate()
            }
        }
    }

    private var addressFieldPlaceholder: String {
        if allowsAirportCodeSearch {
            return "Airport name or code (e.g. LAX, LAS, KLAX)"
        }
        return "e.g. Las Vegas, Bellagio, home address"
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Search the map")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                if showsCurrentLocationButton {
                    Button {
                        currentLocationButtonTapped()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                            Text("Current location")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if allowsAirportCodeSearch {
                Text("Enter a 3-letter IATA or 4-letter ICAO code, or search by airport name.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField(addressFieldPlaceholder, text: $addressQuery)
                    .textInputAutocapitalization(allowsAirportCodeSearch ? .characters : .words)
                    .autocorrectionDisabled(allowsAirportCodeSearch)
                    .submitLabel(.search)
                    .onSubmit { searchFromQueryField() }
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.25))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                Button {
                    searchFromQueryField()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
                .disabled(addressQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal)

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView().tint(.green)
                    Text("Searching…")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
            }

            Map(coordinateRegion: $region, annotationItems: searchResults) { place in
                MapAnnotation(coordinate: place.coordinate) {
                    Button {
                        applyMapPlace(place)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text(place.name)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(height: 220)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray6).opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal)

            if let error = searchError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or enter manually")
                .font(.headline)
                .foregroundColor(.white)
            TextField("Name", text: $manualName)
                .padding(12)
                .background(Color(.systemGray6).opacity(0.25))
                .cornerRadius(10)
                .foregroundColor(.white)
            TextField("Note (optional)", text: $manualSubtitle)
                .padding(12)
                .background(Color(.systemGray6).opacity(0.25))
                .cornerRadius(10)
                .foregroundColor(.white)

            Button {
                let n = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty else { return }
                name = n
                subtitle = manualSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                latitude = nil
                longitude = nil
                dismiss()
            } label: {
                Text("Use manual entry")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.9))
                    .cornerRadius(12)
            }
            .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            if searchResults.isEmpty && !isSearching {
                Text("Search above, or pick a pin on the map.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            } else {
                ForEach(searchResults) { place in
                    Button {
                        applyMapPlace(place)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundColor(.white)
                                if !place.subtitle.isEmpty {
                                    Text(place.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        .padding(10)
                        .background(Color(.systemGray6).opacity(0.25))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func applyUserLocationToMap(_ location: CLLocation) {
        let r = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        region = r
        performLandmarkSearch(in: r)
    }

    private func handleLocationUpdate() {
        guard let loc = locationManager.lastLocation else { return }
        if pendingManualRecenter {
            pendingManualRecenter = false
            applyUserLocationToMap(loc)
            return
        }
        if !hasLocatedOnce {
            hasLocatedOnce = true
            applyUserLocationToMap(loc)
        }
    }

    private func currentLocationButtonTapped() {
        searchError = nil
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            searchError = "Location is off. Enable it in Settings to use Current location."
            return
        case .notDetermined:
            pendingManualRecenter = true
            locationManager.requestWhenInUse()
            return
        default:
            break
        }
        if let loc = locationManager.lastLocation {
            applyUserLocationToMap(loc)
            return
        }
        pendingManualRecenter = true
        locationManager.requestSingleLocationUpdate()
    }

    private func searchFromQueryField() {
        let trimmed = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil

        let query = lookupQuery(from: trimmed)

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(query) { placemarks, error in
            DispatchQueue.main.async {
                if let coordinate = placemarks?.first?.location?.coordinate {
                    let r = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
                    self.region = r
                    // Use the same category search as “Current location” (e.g. hotel / casino / airport), not the free‑text geocode string.
                    self.performLandmarkSearch(in: r)
                    return
                }
                if self.allowsAirportCodeSearch, self.looksLikeAirportCode(trimmed) {
                    let wide = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 25, longitude: -40),
                        span: MKCoordinateSpan(latitudeDelta: 62, longitudeDelta: 124)
                    )
                    self.region = wide
                    self.searchError = nil
                    self.performLandmarkSearch(in: wide)
                    return
                }
                self.isSearching = false
                self.searchError = error?.localizedDescription ?? "Could not find that place."
            }
        }
    }

    private func looksLikeAirportCode(_ trimmed: String) -> Bool {
        let u = trimmed.uppercased()
        if u.count == 3 { return u.allSatisfy(\.isLetter) }
        if u.count == 4 { return u.allSatisfy(\.isLetter) }
        return false
    }

    /// Query sent to geocoder / `MKLocalSearch` so short codes resolve to airports.
    private func lookupQuery(from rawTrimmed: String) -> String {
        let trimmed = rawTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsAirportCodeSearch, looksLikeAirportCode(trimmed) else {
            return trimmed
        }
        return "\(trimmed.uppercased()) airport"
    }

    private func performLandmarkSearch(in region: MKCoordinateRegion) {
        performTextSearch(query: defaultLandmarkQuery, in: region)
    }

    private func performTextSearch(query: String, in region: MKCoordinateRegion) {
        isSearching = true
        searchError = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region

        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false
                if let error = error {
                    self.searchError = error.localizedDescription
                    self.searchResults = []
                    return
                }
                guard let items = response?.mapItems, !items.isEmpty else {
                    self.searchError = "No matches in this area. Try a different search."
                    self.searchResults = []
                    return
                }
                self.searchError = nil
                self.searchResults = items.compactMap { item in
                    let placemark = item.placemark
                    let name = item.name ?? query
                    let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let sub = parts.joined(separator: " · ")
                    return NearbyCasino(
                        name: name,
                        subtitle: sub,
                        coordinate: placemark.coordinate,
                        countryCode: placemark.isoCountryCode,
                        addressComponents: [:]
                    )
                }
            }
        }
    }

    private func applyMapPlace(_ place: NearbyCasino) {
        if preferIataAirportCode,
           let iata = AirportCatalog.iataForMapSelection(coordinate: place.coordinate, mapName: place.name) {
            name = iata
        } else {
            name = place.name
        }
        subtitle = place.subtitle
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        dismiss()
    }
}
