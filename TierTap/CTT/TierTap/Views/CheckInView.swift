import SwiftUI

struct CheckInView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var startingTier = ""
    @State private var initialBuyIn = ""
    @State private var showGamePicker = false
    @State private var showExistingAlert = false
    @State private var showBuyInPicker = false
    @State private var showCasinoLocationPicker = false

    /// Games to show as main grid: favorites only; fallback to pinned if no favorites set.
    private var displayGames: [String] {
        if !settingsStore.favoriteGames.isEmpty { return settingsStore.favoriteGames }
        return GamesList.pinned
    }

    private var isGameInDisplayList: Bool {
        selectedGame.isEmpty || displayGames.contains(selectedGame)
    }

    /// Build a large set of common buy-in amounts from settings denominations + common squares,
    /// and extend in regular increments up to 100k so the grid can keep scrolling upward.
    private var buyInGridAmounts: [Int] {
        let base = settingsStore.effectiveDenominations
        let denoms = base.isEmpty ? [100, 200, 300, 500, 1000, 2000, 5000, 10_000] : base
        var set: Set<Int> = Set(denoms)

        // Core multiples/halves around the configured denominations.
        for d in denoms {
            set.insert(d)
            set.insert(d * 2)
            set.insert(d * 3)
            if d >= 100 { set.insert(d / 2) }
        }

        // Extra "nice" chips.
        set.insert(25); set.insert(50); set.insert(75); set.insert(150); set.insert(250); set.insert(750)

        // Ensure amounts continue in clean increments up to 100k so the grid keeps scrolling.
        let maxTarget = 100_000
        let step = 1_000
        let currentMax = set.max() ?? 0
        if currentMax < maxTarget {
            var next = max(step, ((currentMax + step - 1) / step) * step)
            while next <= maxTarget {
                set.insert(next)
                next += step
            }
        }

        return set.sorted()
    }

    var isValid: Bool {
        !selectedGame.isEmpty && !casino.isEmpty &&
        (Int(startingTier) != nil) && (Int(initialBuyIn) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Gaming Details section: Game on the left, Location on the right
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gaming Details")
                                .font(.headline)
                                .foregroundColor(.white)

                            HStack(alignment: .top, spacing: 12) {
                                // Game — favorites only; More games to browse/select any (including favorites)
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Casino Game", systemImage: "suit.club.fill")
                                        .font(.headline).foregroundColor(.white)
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(displayGames, id: \.self) { g in
                                            GameButton(title: g, isSelected: selectedGame == g) { selectedGame = g }
                                        }
                                    }
                                    Button { showGamePicker = true } label: {
                                        HStack {
                                            Image(systemName: "magnifyingglass")
                                            Text(isGameInDisplayList && selectedGame.isEmpty
                                                 ? "More games..." : selectedGame)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                        .padding(12)
                                        .background(!isGameInDisplayList
                                                    ? Color.green.opacity(0.2) : Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(!isGameInDisplayList ? .white : .gray)
                                        .cornerRadius(10)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6).opacity(0.15))
                                .cornerRadius(16)
                                .frame(maxWidth: .infinity)

                                // Casino — favorites chips + text field + location-based picker
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Casino Location", systemImage: "building.columns")
                                        .font(.headline).foregroundColor(.white)
                                    if !settingsStore.favoriteCasinos.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(settingsStore.favoriteCasinos, id: \.self) { name in
                                                    Button(name) { casino = name }
                                                        .font(.subheadline)
                                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                                        .background(casino == name ? Color.green : Color(.systemGray6).opacity(0.25))
                                                        .foregroundColor(casino == name ? .black : .white)
                                                        .cornerRadius(10)
                                                }
                                            }
                                        }
                                    }
                                    TextField("Enter casino name", text: $casino)
                                        .textFieldStyle(DarkTextFieldStyle())
                                    Button {
                                        showCasinoLocationPicker = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "location.circle")
                                            Text("Find casino near me")
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                        .padding(12)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6).opacity(0.15))
                                .cornerRadius(16)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        // Starting Tier — scrollable wheel (up to 6 figures) + optional text
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Starting Tier Points", systemImage: "star.circle")
                                .font(.headline).foregroundColor(.white)
                            Text("Check your casino loyalty app. Use wheel or type exact.")
                                .font(.caption).foregroundColor(.gray)
                            TierPointsWheel(selectedValue: $startingTier)
                            TextField("Or type exact value", text: $startingTier)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Buy-In — popup first, then big grid of common amounts
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Initial Buy-In", systemImage: "dollarsign.circle")
                                .font(.headline).foregroundColor(.white)
                            Button { showBuyInPicker = true } label: {
                                HStack {
                                    Text(initialBuyIn.isEmpty ? "Choose amount" : "$\(initialBuyIn)")
                                        .font(.title3.bold())
                                    Spacer()
                                    Image(systemName: "square.grid.2x2.fill")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            TextField("Or enter amount", text: $initialBuyIn)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                            if settingsStore.unitSize > 0, (Int(initialBuyIn) ?? 0) > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Buy-in ($\(initialBuyIn)) exceeds your unit size ($\(settingsStore.unitSize)). Consider lowering to stay within bankroll target.")
                                        .font(.caption).foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        Button {
                            if store.liveSession != nil { showExistingAlert = true } else { go() }
                        } label: {
                            Text("Let’s F@#$@ Go!")
                                .frame(maxWidth: .infinity).padding()
                                .background(isValid ? Color.green : Color.gray)
                                .foregroundColor(isValid ? .black : .white)
                                .cornerRadius(14).font(.headline)
                        }
                        .disabled(!isValid)
                        .padding(.bottom, 24)
                    }
                    .padding()
                }
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCasinoLocationPicker) {
                CasinoLocationPickerView(selectedCasino: $casino)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showBuyInPicker) {
                BuyInGridSheet(amounts: buyInGridAmounts, selected: $initialBuyIn)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .alert("Active Session", isPresented: $showExistingAlert) {
                Button("Resume Existing", role: .cancel) { dismiss() }
                Button("End & Start New", role: .destructive) { store.discardLiveSession(); go() }
            } message: {
                Text("You have a live session. Resume it or end it to start a new one?")
            }
        }
    }

    func go() {
        guard let tier = Int(startingTier), let buy = Int(initialBuyIn) else { return }
        store.startSession(game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: buy)
        dismiss()
    }
}
