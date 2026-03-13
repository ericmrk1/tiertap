import SwiftUI

struct CheckInView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var isCasinoPublic = true
    @State private var startingTier = "0"
    @State private var initialBuyIn = ""
    @State private var selectedRewardsProgram = ""
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

    /// Known casino loyalty / rewards programs. For now this is hard-coded and
    /// matched loosely against the selected casino name.
    private let defaultRewardPrograms: [String] = [
        "MGM Rewards",
        "Caesars Rewards",
        "Wynn Rewards",
        "Grazie Rewards",
        "Identity Rewards",
        "B Connected",
        "Club One",
        "Club Serrano"
    ]

    private let casinoRewardPrograms: [String: [String]] = [
        "MGM": ["MGM Rewards"],
        "Bellagio": ["MGM Rewards"],
        "Aria": ["MGM Rewards"],
        "Cosmopolitan": ["Identity Rewards"],
        "Caesars": ["Caesars Rewards"],
        "Harrah": ["Caesars Rewards"],
        "Paris": ["Caesars Rewards"],
        "Wynn": ["Wynn Rewards"],
        "Encore": ["Wynn Rewards"],
        "Venetian": ["Grazie Rewards"],
        "Palazzo": ["Grazie Rewards"],
        "Palms": ["Club Serrano"],
        "Boyd": ["B Connected"]
    ]

    private var availableRewardPrograms: [String] {
        guard !casino.isEmpty else { return defaultRewardPrograms }
        let matches = casinoRewardPrograms.compactMap { key, programs in
            casino.localizedCaseInsensitiveContains(key) ? programs : nil
        }
        let flattened = matches.flatMap { $0 }
        let unique = Array(Set(flattened))
        return unique.isEmpty ? defaultRewardPrograms : unique
    }

    var isValid: Bool {
        !selectedGame.isEmpty && !casino.isEmpty &&
        (Int(startingTier) != nil) && (Int(initialBuyIn) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                    // Gaming Details section: vertically stacked Game then Location
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gaming Details")
                            .font(.headline)
                            .foregroundColor(.white)

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

                        // Casino — favorites chips + text field + location-based picker + public toggle
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Casino Location", systemImage: "building.columns")
                                    .font(.headline).foregroundColor(.white)
                                Spacer()
                                Toggle(isOn: $isCasinoPublic) {
                                    Text(isCasinoPublic ? "Public" : "Private")
                                        .font(.caption)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                            }
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
                    }

                    // Starting Tier — header with rewards selector, wheel, and value entry
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Label("Starting Tier Points", systemImage: "star.circle")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            if !availableRewardPrograms.isEmpty {
                                Picker("", selection: $selectedRewardsProgram) {
                                    Text("Select Rewards").tag("").font(.caption)
                                    ForEach(availableRewardPrograms, id: \.self) { program in
                                        Text(program).tag(program)
                                    }
                                }
                                .pickerStyle(.menu)
                                .font(.caption) // smaller font for the selector
                                .tint(.white)
                            }
                        }
                        Text("Check your casino loyalty app. Use wheel or type exact.")
                            .font(.caption).foregroundColor(.gray)
                        HStack(spacing: 12) {
                            TierPointsWheel(selectedValue: $startingTier)
                                .frame(maxWidth: .infinity)
                            TextField("Exact value", text: $startingTier)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                                .frame(width: 110)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.15))
                    .cornerRadius(16)

                    // Buy-In — selector on left, value + rewards program on right
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Initial Buy-In", systemImage: "dollarsign.circle")
                            .font(.headline).foregroundColor(.white)
                        HStack(alignment: .top, spacing: 12) {
                            // Left: quick-select grid launcher for common cash amounts
                            Button { showBuyInPicker = true } label: {
                                HStack {
                                    Image(systemName: "square.grid.2x2.fill")
                                Text(initialBuyIn.isEmpty ? "Choose cash" : "\(settingsStore.currencySymbol)\(initialBuyIn)")
                                        .lineLimit(1)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .frame(maxWidth: .infinity)

                            // Right: typed value
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Exact amount", text: $initialBuyIn)
                                    .textFieldStyle(DarkTextFieldStyle())
                                    .keyboardType(.numberPad)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if settingsStore.unitSize > 0, (Int(initialBuyIn) ?? 0) > settingsStore.unitSize {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Buy-in (\(settingsStore.currencySymbol)\(initialBuyIn)) exceeds your unit size (\(settingsStore.currencySymbol)\(settingsStore.unitSize)). Consider lowering to stay within bankroll target.")
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
                        .padding(.bottom, 8)
                        .padding(.horizontal)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .adaptiveSheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showCasinoLocationPicker) {
                NavigationStack {
                    CasinoLocationPickerView(selectedCasino: $casino)
                        .environmentObject(settingsStore)
                }
            }
            .adaptiveSheet(isPresented: $showBuyInPicker) {
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
            .onAppear {
                if casino.isEmpty, let recent = store.mostRecentCasino() {
                    casino = recent
                }
            }
        }
    }

    func go() {
        guard let tier = Int(startingTier), let buy = Int(initialBuyIn) else { return }
        // Best-effort insert of the chosen game into Supabase master list.
        TableGamesAPI.insertIfPossible(selectedGame)
        // Best-effort insert of the casino location; when typed we won't have coordinates.
        CasinoLocationsAPI.insertTyped(name: casino, isPublic: isCasinoPublic, userId: nil)
        store.startSession(game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: buy)
        if settingsStore.enableCasinoFeedback {
            CelebrationPlayer.shared.playQuickChime()
        }
        dismiss()
    }
}
