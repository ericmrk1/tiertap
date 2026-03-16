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
    // Casino game type metadata
    @State private var gameCategory: SessionGameCategory = .table
    @State private var pokerGameKind: SessionPokerGameKind = .cash
    @State private var pokerAllowsRebuy: Bool = false
    @State private var pokerAllowsAddOn: Bool = false
    @State private var pokerHasFreezeOut: Bool = false
    @State private var pokerVariant: String = "No Limit Texas Hold’em"
    @State private var pokerSmallBlind: Int = 0
    @State private var pokerBigBlind: Int = 0
    @State private var pokerAnte: Int = 0
    @State private var pokerLevelMinutesText: String = ""
    @State private var pokerStartingStackText: String = ""
    @State private var pokerTournamentCostText: String = "0"
    @State private var showCasinoLocationPicker = false

    /// Games to show as main grid: favorites only; fallback to pinned if no favorites set.
    private var displayGames: [String] {
        if !settingsStore.favoriteGames.isEmpty { return settingsStore.favoriteGames }
        return GamesList.pinned
    }

    /// Simple pill-style toggle used for Table/Poker and Cash/Tournament.
    private struct GameTypePill: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isSelected ? .black : .white)
                    .clipShape(Capsule())
            }
        }
    }

    /// Chip-style multi-select for tournament options.
    private struct OptionChip: View {
        let title: String
        let isOn: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isOn ? Color.green.opacity(0.2) : Color(.systemGray6).opacity(0.25))
                    .foregroundColor(isOn ? .green : .white)
                    .cornerRadius(8)
            }
        }
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
        let hasGame: Bool = (gameCategory == .poker) ? true : !selectedGame.isEmpty
        return hasGame && !casino.isEmpty &&
        (Int(startingTier) != nil) && (Int(initialBuyIn) ?? 0) > 0
    }

    /// Discrete blind values used for SB / BB / Ante wheels and presets.
    private let blindPickerValues: [Int] = [0, 1, 2, 3, 5, 10, 20, 40, 80, 100, 200, 300, 400, 500, 600, 800, 1000]

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

                        // Game — Table or Poker, with detailed Poker metadata when selected
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 8) {
                                Label("Casino Game", systemImage: "suit.club.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    GameTypePill(title: "Table", isSelected: gameCategory == .table) {
                                        gameCategory = .table
                                    }
                                    GameTypePill(title: "Poker", isSelected: gameCategory == .poker) {
                                        gameCategory = .poker
                                        if pokerVariant.isEmpty {
                                            pokerVariant = "No Limit Texas Hold’em"
                                        }
                                    }
                                }
                            }

                            if gameCategory == .table {
                                // Existing table game UI: favorites grid + More games search
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
                            } else {
                                // Poker-specific controls with blinds & structure beneath
                                VStack(alignment: .leading, spacing: 12) {
                                    // Cash vs Tournament with type of game to the right
                                    HStack(alignment: .center, spacing: 8) {
                                        HStack(spacing: 8) {
                                            GameTypePill(title: "Cash", isSelected: pokerGameKind == .cash) {
                                                pokerGameKind = .cash
                                            }
                                            GameTypePill(title: "Tournament", isSelected: pokerGameKind == .tournament) {
                                                pokerGameKind = .tournament
                                            }
                                        }
                                        Spacer()
                                        Picker("Type of Game", selection: $pokerVariant) {
                                            Text("No Limit Texas Hold’em").tag("No Limit Texas Hold’em")
                                            Text("Pot Limit Omaha").tag("Pot Limit Omaha")
                                            Text("Pot Limit Omaha Hi-Lo").tag("Pot Limit Omaha Hi-Lo")
                                            Text("Fixed Limit Hold’em").tag("Fixed Limit Hold’em")
                                            Text("Spread Limit Hold’em").tag("Spread Limit Hold’em")
                                            Text("Short Deck Hold’em (6+)").tag("Short Deck Hold’em (6+)")
                                            Text("Omaha Hi").tag("Omaha Hi")
                                            Text("Omaha Hi-Lo").tag("Omaha Hi-Lo")
                                            Text("5 Card Omaha").tag("5 Card Omaha")
                                            Text("5 Card Omaha Hi-Lo").tag("5 Card Omaha Hi-Lo")
                                            Text("7 Card Stud").tag("7 Card Stud")
                                            Text("7 Card Stud Hi-Lo").tag("7 Card Stud Hi-Lo")
                                            Text("Razz").tag("Razz")
                                            Text("5 Card Draw").tag("5 Card Draw")
                                            Text("2-7 Triple Draw").tag("2-7 Triple Draw")
                                            Text("2-7 Single Draw").tag("2-7 Single Draw")
                                            Text("Chinese Poker").tag("Chinese Poker")
                                            Text("Open Face Chinese").tag("Open Face Chinese")
                                            Text("Mixed Game (H.O.R.S.E.)").tag("Mixed Game (H.O.R.S.E.)")
                                            Text("Mixed Game (8-Game)").tag("Mixed Game (8-Game)")
                                            Text("Other Poker").tag("Other Poker")
                                        }
                                        .pickerStyle(.menu)
                                        .tint(.white)
                                    }

                                    // Tournament re-buy / add-on / freeze-out toggles beneath everything else
                                    if pokerGameKind == .tournament {
                                        HStack(spacing: 8) {
                                            OptionChip(title: "Re-buy", isOn: pokerAllowsRebuy) {
                                                pokerAllowsRebuy.toggle()
                                            }
                                            OptionChip(title: "Add-On", isOn: pokerAllowsAddOn) {
                                                pokerAllowsAddOn.toggle()
                                            }
                                            OptionChip(title: "Freeze-Out", isOn: pokerHasFreezeOut) {
                                                pokerHasFreezeOut.toggle()
                                            }
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Blinds & Structure")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)

                                        HStack(alignment: .center, spacing: 12) {
                                            VStack(spacing: 4) {
                                                Text("SB")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                Picker("SB", selection: $pokerSmallBlind) {
                                                    ForEach(blindPickerValues, id: \.self) { value in
                                                        Text(value == 0 ? "-" : "\(value)")
                                                            .tag(value)
                                                    }
                                                }
                                                .pickerStyle(.wheel)
                                                .frame(height: 80)
                                            }
                                            VStack(spacing: 4) {
                                                Text("BB")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                Picker("BB", selection: $pokerBigBlind) {
                                                    ForEach(blindPickerValues, id: \.self) { value in
                                                        Text(value == 0 ? "-" : "\(value)")
                                                            .tag(value)
                                                    }
                                                }
                                                .pickerStyle(.wheel)
                                                .frame(height: 80)
                                            }
                                            VStack(spacing: 4) {
                                                Text("Ante")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                Picker("Ante", selection: $pokerAnte) {
                                                    ForEach(blindPickerValues, id: \.self) { value in
                                                        Text(value == 0 ? "-" : "\(value)")
                                                            .tag(value)
                                                    }
                                                }
                                                .pickerStyle(.wheel)
                                                .frame(height: 80)
                                            }
                                        }

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                Button("$1/$2") {
                                                    pokerSmallBlind = 1
                                                    pokerBigBlind = 2
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$1/$3") {
                                                    pokerSmallBlind = 1
                                                    pokerBigBlind = 3
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$2/$5") {
                                                    pokerSmallBlind = 2
                                                    pokerBigBlind = 5
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$5/$10") {
                                                    pokerSmallBlind = 5
                                                    pokerBigBlind = 10
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$10/$20") {
                                                    pokerSmallBlind = 10
                                                    pokerBigBlind = 20
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$20/$40") {
                                                    pokerSmallBlind = 20
                                                    pokerBigBlind = 40
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$40/$80") {
                                                    pokerSmallBlind = 40
                                                    pokerBigBlind = 80
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$100/$200") {
                                                    pokerSmallBlind = 100
                                                    pokerBigBlind = 200
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$200/$400") {
                                                    pokerSmallBlind = 200
                                                    pokerBigBlind = 400
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$300/$600") {
                                                    pokerSmallBlind = 300
                                                    pokerBigBlind = 600
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$400/$800") {
                                                    pokerSmallBlind = 400
                                                    pokerBigBlind = 800
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$500/$1000") {
                                                    pokerSmallBlind = 500
                                                    pokerBigBlind = 1000
                                                    pokerAnte = 0
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)

                                                Button("$1/$3/$5") {
                                                    pokerSmallBlind = 1
                                                    pokerBigBlind = 3
                                                    pokerAnte = 5
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6).opacity(0.35))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                            }
                                        }

                                        if pokerGameKind == .tournament {
                                            HStack(spacing: 8) {
                                                TextField("Level mins", text: $pokerLevelMinutesText)
                                                    .textFieldStyle(DarkTextFieldStyle())
                                                    .keyboardType(.numberPad)
                                                TextField("Starting stack", text: $pokerStartingStackText)
                                                    .textFieldStyle(DarkTextFieldStyle())
                                                    .keyboardType(.numberPad)
                                                TextField("Cost", text: $pokerTournamentCostText)
                                                    .textFieldStyle(DarkTextFieldStyle())
                                                    .keyboardType(.numberPad)
                                            }
                                        }
                                    }
                                }
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
            .onChange(of: pokerSmallBlind) { newValue in
                if newValue == 5 && pokerBigBlind != 10 {
                    pokerBigBlind = 10
                }
            }
            .onChange(of: pokerBigBlind) { newValue in
                if newValue == 10 && pokerSmallBlind != 5 {
                    pokerSmallBlind = 5
                }
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
                // Use default from Settings for initial game category.
                gameCategory = settingsStore.defaultGameCategory
            }
        }
    }

    func go() {
        // For Poker, build a descriptive game name from the selected options.
        if gameCategory == .poker {
            var parts: [String] = []
            let kindLabel = (pokerGameKind == .cash) ? "Cash" : "Tournament"
            parts.append("Poker \(kindLabel)")
            if !pokerVariant.isEmpty {
                parts.append(pokerVariant)
            }
            if pokerGameKind == .tournament {
                var opts: [String] = []
                if pokerAllowsRebuy { opts.append("Re-buy") }
                if pokerAllowsAddOn { opts.append("Add-On") }
                if pokerHasFreezeOut { opts.append("Freeze-Out") }
                if !opts.isEmpty {
                    parts.append(opts.joined(separator: ", "))
                }
            }
            selectedGame = parts.joined(separator: " - ")
        }

        guard let tier = Int(startingTier), let buy = Int(initialBuyIn) else { return }
        // Best-effort insert of the chosen game into Supabase master list.
        TableGamesAPI.insertIfPossible(selectedGame)
        // Best-effort insert of the casino location; when typed we won't have coordinates.
        CasinoLocationsAPI.insertTyped(name: casino, isPublic: isCasinoPublic, userId: nil)
        store.startSession(game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: buy)
        // Persist structured game metadata on the live session.
        let category: SessionGameCategory? = gameCategory
        let kind: SessionPokerGameKind? = (gameCategory == .poker) ? pokerGameKind : nil
        let rebuy: Bool? = (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsRebuy : nil
        let addOn: Bool? = (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsAddOn : nil
        let freeOut: Bool? = (gameCategory == .poker && pokerGameKind == .tournament) ? pokerHasFreezeOut : nil
        let variant: String? = (gameCategory == .poker) ? pokerVariant : nil
        let sb: Int? = (gameCategory == .poker && pokerSmallBlind > 0) ? pokerSmallBlind : nil
        let bb: Int? = (gameCategory == .poker && pokerBigBlind > 0) ? pokerBigBlind : nil
        let ante: Int? = (gameCategory == .poker && pokerAnte > 0) ? pokerAnte : nil
        let levelMinutes: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerLevelMinutesText) : nil
        let startingStack: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerStartingStackText) : nil
        store.updateLiveSessionGameMetadata(
            gameCategory: category,
            pokerGameKind: kind,
            pokerAllowsRebuy: rebuy,
            pokerAllowsAddOn: addOn,
            pokerHasFreeOut: freeOut,
            pokerVariant: variant,
            pokerSmallBlind: sb,
            pokerBigBlind: bb,
            pokerAnte: ante,
            pokerLevelMinutes: levelMinutes,
            pokerStartingStack: startingStack
        )
        if settingsStore.enableCasinoFeedback {
            CelebrationPlayer.shared.playQuickChime()
        }
        dismiss()
    }
}
