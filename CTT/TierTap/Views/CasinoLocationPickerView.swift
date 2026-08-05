import SwiftUI
import MapKit
import CoreLocation

struct NearbyCasino: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let countryCode: String?
    let addressComponents: [String: String]
}

struct CasinoLocationPickerView: View {
    @Binding var selectedCasino: String
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.1147, longitude: -115.1728), // Las Vegas default
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var nearbyCasinos: [NearbyCasino] = []
    @State private var isSearching = false
    @State private var hasAutoSearchedOnce = false
    @State private var searchError: String?
    @State private var addressQuery: String = ""
    @State private var pendingCurrentLocationSearch = false

    /// ~1 km — tight enough to surface the casino you're standing in on a dense strip.
    private let preciseSearchSpan = MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
    /// ~25 km — broader lookup when geocoding a city or ZIP.
    private let addressSearchSpan = MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    mapSection
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            favoritesSection
                            nearbySection
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                }
            }
            .localizedNavigationTitle("Select Casino")
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
                searchNearCurrentLocation()
            }
            .onChange(of: locationManager.lastLocation) { _ in
                handleLocationUpdate()
            }
            .onChange(of: locationManager.authorizationStatus) { _ in
                handleAuthorizationChange()
            }
        }
    }

    // MARK: - Sections

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                L10nText("Search by ZIP code or address")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                Button {
                    searchNearCurrentLocation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        L10nText("Current location")
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
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("e.g. 89109 or 123 Main St", text: $addressQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .onSubmit {
                            searchByAddressOrZip()
                        }
                        .padding(10)
                        .background(Color(.systemGray6).opacity(0.25))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                    Button {
                        searchByAddressOrZip()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                    }
                    .disabled(addressQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(addressQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                }
            }
            .padding(.horizontal)

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.green)
                    L10nText("Searching for nearby casinos…")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Map(coordinateRegion: $region, annotationItems: nearbyCasinos) { casino in
                MapAnnotation(coordinate: casino.coordinate) {
                    Button {
                        select(casino: casino)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text(casino.name)
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
            } else if authorizationMessage != nil {
                Text(authorizationMessage!)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 16)
    }

    private var favoritesSection: some View {
        Group {
            if !settingsStore.favoriteCasinos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    L10nText("Saved Locations")
                        .font(.headline)
                        .foregroundColor(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(settingsStore.favoriteCasinos, id: \.self) { name in
                                Button(name) {
                                    selectedCasino = name
                                    dismiss()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedCasino == name ? Color.green : Color(.systemGray6).opacity(0.25))
                                .foregroundColor(selectedCasino == name ? .black : .white)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            L10nText("Casinos Near You")
                .font(.headline)
                .foregroundColor(.white)

            if nearbyCasinos.isEmpty {
                if !isSearching && hasAutoSearchedOnce {
                    L10nText("No nearby casinos found. Try again closer to a property or check saved locations.")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else if !isSearching {
                    L10nText("Waiting for your location…")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                ForEach(nearbyCasinos) { casino in
                    Button {
                        select(casino: casino)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(casino.name)
                                    .foregroundColor(.white)
                                if !casino.subtitle.isEmpty {
                                    Text(casino.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(10)
                        .background(Color(.systemGray6).opacity(0.25))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var authorizationMessage: String? {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location access is turned off. Enable it in Settings to see nearby casinos, or use your saved locations."
        case .notDetermined:
            return "Grant location access to search casinos near you, or search by ZIP/address or pick from saved locations."
        default:
            return nil
        }
    }

    private func handleLocationUpdate() {
        guard pendingCurrentLocationSearch, let loc = locationManager.lastLocation else { return }
        pendingCurrentLocationSearch = false
        applyPreciseSearch(around: loc)
    }

    private func handleAuthorizationChange() {
        guard pendingCurrentLocationSearch else { return }
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = locationManager.lastLocation {
                pendingCurrentLocationSearch = false
                applyPreciseSearch(around: loc)
            } else {
                locationManager.requestSingleLocationUpdate()
            }
        default:
            break
        }
    }

    private func searchNearCurrentLocation() {
        searchError = nil
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            searchError = "Location is off. Enable it in Settings to search near your current position."
            return
        case .notDetermined:
            pendingCurrentLocationSearch = true
            locationManager.requestWhenInUse()
            return
        default:
            break
        }
        if let loc = locationManager.lastLocation {
            applyPreciseSearch(around: loc)
            return
        }
        pendingCurrentLocationSearch = true
        locationManager.requestSingleLocationUpdate()
    }

    private func applyPreciseSearch(around location: CLLocation) {
        hasAutoSearchedOnce = true
        let newRegion = MKCoordinateRegion(center: location.coordinate, span: preciseSearchSpan)
        region = newRegion
        performCasinoSearch(in: newRegion, sortFrom: location.coordinate)
    }

    private func searchByAddressOrZip() {
        let trimmed = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        searchError = nil

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(trimmed) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.isSearching = false
                    self.searchError = "Could not find that location: \(error.localizedDescription)"
                    return
                }
                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    self.isSearching = false
                    self.searchError = "Could not find that location. Try a different ZIP or address."
                    return
                }

                let newRegion = MKCoordinateRegion(center: coordinate, span: self.addressSearchSpan)
                self.region = newRegion
                self.performCasinoSearch(in: newRegion, sortFrom: coordinate)
            }
        }
    }

    private func performCasinoSearch(in region: MKCoordinateRegion, sortFrom center: CLLocationCoordinate2D) {
        isSearching = true
        searchError = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "casino"
        request.region = region

        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false
                if let error = error {
                    self.searchError = "Could not search nearby casinos: \(error.localizedDescription)"
                    return
                }
                guard let items = response?.mapItems, !items.isEmpty else {
                    self.searchError = "No casinos found for that area."
                    self.nearbyCasinos = []
                    return
                }
                let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let sortedItems = items.sorted {
                    let a = $0.placemark.location ?? CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                    let b = $1.placemark.location ?? CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                    return origin.distance(from: a) < origin.distance(from: b)
                }
                self.nearbyCasinos = sortedItems.compactMap { item in
                    let placemark = item.placemark
                    let name = item.name ?? "Casino"
                    let locality = placemark.locality
                    let admin = placemark.administrativeArea
                    let locationLine = [locality, admin].compactMap { $0 }.joined(separator: ", ")
                    let casinoLocation = placemark.location ?? CLLocation(
                        latitude: placemark.coordinate.latitude,
                        longitude: placemark.coordinate.longitude
                    )
                    let miles = origin.distance(from: casinoLocation) / 1609.34
                    let distanceLine = miles < 0.1 ? "Right nearby" : String(format: "%.1f mi away", miles)
                    let subtitle = locationLine.isEmpty ? distanceLine : "\(distanceLine) · \(locationLine)"
                    let isoCountry = placemark.isoCountryCode

                    var addressDict: [String: String] = [:]
                    func put(_ key: String, _ value: String?) {
                        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
                        addressDict[key] = v
                    }

                    // Core address fields
                    let streetNumber = placemark.subThoroughfare
                    let streetName = placemark.thoroughfare
                    let fullStreet = [streetNumber, streetName].compactMap { $0 }.joined(separator: " ")

                    put("streetNumber", streetNumber)
                    put("streetName", streetName)
                    put("street", fullStreet)
                    put("city", placemark.locality)
                    put("state", placemark.administrativeArea)
                    put("postalCode", placemark.postalCode)
                    put("subLocality", placemark.subLocality)
                    put("subAdministrativeArea", placemark.subAdministrativeArea)
                    put("country", placemark.country)
                    put("countryCode", placemark.isoCountryCode)

                    // Region metadata when available
                    if let region = placemark.region as? CLCircularRegion {
                        put("regionIdentifier", region.identifier)
                        put("regionRadiusMeters", String(region.radius))
                        put("regionCenterLat", String(region.center.latitude))
                        put("regionCenterLng", String(region.center.longitude))
                    }

                    return NearbyCasino(
                        name: name,
                        subtitle: subtitle,
                        coordinate: placemark.coordinate,
                        countryCode: isoCountry,
                        addressComponents: addressDict
                    )
                }
            }
        }
    }

    private func select(casino: NearbyCasino) {
        selectedCasino = casino.name
        selectedLatitude = casino.coordinate.latitude
        selectedLongitude = casino.coordinate.longitude

        let canShareToCloud = authStore.isSignedIn
            && (subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive)
        if canShareToCloud {
            let coordinate = casino.coordinate
            CasinoLocationsAPI.insertPicked(
                name: casino.name,
                addressComponents: casino.addressComponents,
                coordinate: coordinate,
                isPublic: true,
                userId: nil
            )
        }

        dismiss()
    }
}

