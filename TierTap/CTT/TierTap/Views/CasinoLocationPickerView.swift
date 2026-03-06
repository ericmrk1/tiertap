import SwiftUI
import MapKit

struct NearbyCasino: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

struct CasinoLocationPickerView: View {
    @Binding var selectedCasino: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsStore: SettingsStore

    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.1147, longitude: -115.1728), // Las Vegas default
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var nearbyCasinos: [NearbyCasino] = []
    @State private var isSearching = false
    @State private var hasSearchedOnce = false
    @State private var searchError: String?

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
            .navigationTitle("Select Casino")
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
            }
            .onChange(of: locationManager.lastLocation) { _ in
                triggerSearchIfNeeded()
            }
        }
    }

    // MARK: - Sections

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.green)
                    Text("Searching for nearby casinos…")
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
                    Text("Saved Locations")
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
            Text("Casinos Near You")
                .font(.headline)
                .foregroundColor(.white)

            if nearbyCasinos.isEmpty {
                if !isSearching && hasSearchedOnce {
                    Text("No nearby casinos found. Try again closer to a property or check saved locations.")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else if !isSearching {
                    Text("Waiting for your location…")
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
            return "Grant location access to help find casinos near you, or pick from your saved locations."
        default:
            return nil
        }
    }

    private func triggerSearchIfNeeded() {
        guard let loc = locationManager.lastLocation, !hasSearchedOnce else { return }
        hasSearchedOnce = true
        isSearching = true
        searchError = nil

        let span = MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        region = MKCoordinateRegion(center: loc.coordinate, span: span)

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
                guard let items = response?.mapItems else {
                    self.searchError = "No nearby casinos found."
                    return
                }
                self.nearbyCasinos = items.compactMap { item in
                    let name = item.name ?? "Casino"
                    let locality = item.placemark.locality
                    let admin = item.placemark.administrativeArea
                    let subtitle = [locality, admin].compactMap { $0 }.joined(separator: ", ")
                    return NearbyCasino(name: name,
                                        subtitle: subtitle,
                                        coordinate: item.placemark.coordinate)
                }
            }
        }
    }

    private func select(casino: NearbyCasino) {
        selectedCasino = casino.name
        dismiss()
    }
}

