import SwiftUI

struct CheckInView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var isCasinoPublic = true
    @State private var startingTier = "0"
    @State private var initialBuyIn = ""
    @State private var selectedRewardsProgram = ""
    @State private var showGamePicker = false
    @State private var showExistingAlert = false
    @State private var showTierTrackingWarning = false
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
    @State private var slotNotes: String = ""
    @State private var showCasinoLocationPicker = false
    @State private var casinoLatitude: Double?
    @State private var casinoLongitude: Double?

    /// Games to show as main grid: favorites only; fallback to pinned if no favorites set.
    private var displayGames: [String] {
        if !settingsStore.favoriteGames.isEmpty { return settingsStore.favoriteGames }
        return GamesList.pinned
    }

    /// Slot titles for the grid when category is Slots (favorites, else pinned).
    private var displaySlots: [String] {
        if !settingsStore.favoriteSlotGames.isEmpty { return settingsStore.favoriteSlotGames }
        return SlotsList.pinned
    }

    /// Titles for the Table or Slots quick-pick grid.
    private var activeGameGridTitles: [String] {
        switch gameCategory {
        case .table: return displayGames
        case .slots: return displaySlots
        case .poker: return []
        }
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
        let list = gameCategory == .slots ? displaySlots : displayGames
        return selectedGame.isEmpty || list.contains(selectedGame)
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
        return hasGame && !casino.isEmpty && (Int(initialBuyIn) ?? 0) > 0
    }

    /// True when tier field is empty, non-numeric, or zero or negative — session may still start after confirmation.
    private var needsTierTrackingWarning: Bool {
        let s = startingTier.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        guard let t = Int(s) else { return true }
        return t <= 0
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
                        L10nText("Gaming Details")
                            .font(.headline)
                            .foregroundColor(.white)

                        // Game — Table / Slots / Poker (wheel); Poker details below when selected
                        VStack(alignment: .leading, spacing: 10) {
                            LocalizedLabel(title: "Casino Game", systemImage: "suit.club.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                            GameCategoryWheelPicker(selection: $gameCategory, heading: "Game Type")
                                .environmentObject(settingsStore)

                            if gameCategory == .table || gameCategory == .slots {
                                // Table or Slots: favorites grid + More games search (slot list is slots-only)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(activeGameGridTitles, id: \.self) { g in
                                        GameButton(title: g, isSelected: selectedGame == g) { selectedGame = g }
                                    }
                                }
                                GamePickerSelectorRow(
                                    title: isGameInDisplayList && selectedGame.isEmpty
                                        ? "More games..." : selectedGame,
                                    accentHighlighted: !isGameInDisplayList,
                                    isPlaceholder: isGameInDisplayList && selectedGame.isEmpty,
                                    showSearchIcon: true
                                ) { showGamePicker = true }
                                    .environmentObject(settingsStore)
                                if gameCategory == .slots {
                                    SlotSessionNotesOnlySection(slotNotes: $slotNotes)
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
                                            L10nText("No Limit Texas Hold’em").tag("No Limit Texas Hold’em")
                                            L10nText("Pot Limit Omaha").tag("Pot Limit Omaha")
                                            L10nText("Pot Limit Omaha Hi-Lo").tag("Pot Limit Omaha Hi-Lo")
                                            L10nText("Fixed Limit Hold’em").tag("Fixed Limit Hold’em")
                                            L10nText("Spread Limit Hold’em").tag("Spread Limit Hold’em")
                                            L10nText("Short Deck Hold’em (6+)").tag("Short Deck Hold’em (6+)")
                                            L10nText("Omaha Hi").tag("Omaha Hi")
                                            L10nText("Omaha Hi-Lo").tag("Omaha Hi-Lo")
                                            L10nText("5 Card Omaha").tag("5 Card Omaha")
                                            L10nText("5 Card Omaha Hi-Lo").tag("5 Card Omaha Hi-Lo")
                                            L10nText("7 Card Stud").tag("7 Card Stud")
                                            L10nText("7 Card Stud Hi-Lo").tag("7 Card Stud Hi-Lo")
                                            L10nText("Razz").tag("Razz")
                                            L10nText("5 Card Draw").tag("5 Card Draw")
                                            L10nText("2-7 Triple Draw").tag("2-7 Triple Draw")
                                            L10nText("2-7 Single Draw").tag("2-7 Single Draw")
                                            L10nText("Chinese Poker").tag("Chinese Poker")
                                            L10nText("Open Face Chinese").tag("Open Face Chinese")
                                            L10nText("Mixed Game (H.O.R.S.E.)").tag("Mixed Game (H.O.R.S.E.)")
                                            L10nText("Mixed Game (8-Game)").tag("Mixed Game (8-Game)")
                                            L10nText("Other Poker").tag("Other Poker")
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
                                        L10nText("Blinds & Structure")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)

                                        HStack(alignment: .center, spacing: 12) {
                                            VStack(spacing: 4) {
                                                L10nText("SB")
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
                                                L10nText("BB")
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
                                                L10nText("Ante")
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
                                LocalizedLabel(title: "Casino Location", systemImage: "building.columns")
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
                                    L10nText("Find casino near me")
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

                    // Starting Tier — header with rewards selector, quick-pick grid, and value entry
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            LocalizedLabel(title: "Starting Tier Points", systemImage: "star.circle")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            if !availableRewardPrograms.isEmpty {
                                Picker("", selection: $selectedRewardsProgram) {
                                    L10nText("Select Rewards").tag("").font(.caption)
                                    ForEach(availableRewardPrograms, id: \.self) { program in
                                        Text(program).tag(program)
                                    }
                                }
                                .pickerStyle(.menu)
                                .font(.caption) // smaller font for the selector
                                .tint(.white)
                            }
                        }
                        L10nText("Check your casino loyalty app. Quick pick 1,000–50,000 or type any exact amount. Starting at zero is allowed but harder to track.")
                            .font(.caption).foregroundColor(.gray)
                        TierPointsQuickPickRow(tierPointsText: $startingTier)
                            .environmentObject(settingsStore)
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.15))
                    .cornerRadius(16)

                    // Buy-In — selector on left, value + rewards program on right
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedLabel(title: "Initial Buy-In", systemImage: "dollarsign.circle")
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
                            if store.liveSession != nil {
                                showExistingAlert = true
                            } else {
                                attemptGo()
                            }
                        } label: {
                            L10nText("Let’s F@#$@ Go!")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 16)
                                .font(.headline)
                                .foregroundColor(isValid ? .white : .white.opacity(0.85))
                                .background {
                                    if isValid {
                                        GameCategoryBubbleBackground(cornerRadius: 14)
                                    } else {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.gray)
                                    }
                                }
                        }
                        .disabled(!isValid)
                        .padding(.bottom, 8)
                        .padding(.horizontal)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .localizedNavigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .adaptiveSheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame, mode: gameCategory == .slots ? .slots : .table)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                    .gamePickerSheetPresentation()
            }
            .fullScreenCover(isPresented: $showCasinoLocationPicker) {
                NavigationStack {
                    CasinoLocationPickerView(selectedCasino: $casino, selectedLatitude: $casinoLatitude, selectedLongitude: $casinoLongitude)
                        .environmentObject(settingsStore)
                        .environmentObject(authStore)
                        .environmentObject(subscriptionStore)
                }
            }
            .adaptiveSheet(isPresented: $showBuyInPicker) {
                BuyInGridSheet(amounts: settingsStore.buyInGridAmounts, selected: $initialBuyIn)
                    .environmentObject(settingsStore)
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
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
                Button("End & Start New", role: .destructive) {
                    store.discardLiveSession()
                    attemptGo()
                }
            } message: {
                L10nText("You have a live session. Resume it or end it to start a new one?")
            }
            .alert(
                Text(L10n.tr("Tier points", language: settingsStore.appLanguage)),
                isPresented: $showTierTrackingWarning
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Start anyway") { go(skipTierTrackingWarning: true) }
            } message: {
                Text(L10n.tr("Starting sessions without a Tier rating will make it difficult to track Tier levels and points.", language: settingsStore.appLanguage))
            }
            .onAppear {
                if casino.isEmpty, let recent = store.mostRecentCasino() {
                    casino = recent
                }
                gameCategory = settingsStore.defaultGameCategory
                applyLastSavedGameDefaults()
                applyCasinoHistoryDefaults()
            }
            .onChange(of: casino) { _ in
                applyCasinoHistoryDefaults()
            }
            .onChange(of: gameCategory) { newCat in
                if newCat != .slots {
                    slotNotes = ""
                }
                applyLastSavedGameDefaults()
            }
        }
    }

    /// Pre-fills starting tier points and initial buy-in from the most recent session at this
    /// exact casino name (when that history exists). Skips while typing a new name that does
    /// not yet match a saved session.
    private func applyCasinoHistoryDefaults() {
        guard store.hasSessionHistory(forExactCasino: casino) else { return }
        if let tier = store.defaultEndingTierPoints(for: casino) {
            startingTier = "\(tier)"
        }
        if let buy = store.defaultInitialBuyIn(for: casino) {
            initialBuyIn = "\(buy)"
        }
    }

    /// Pre-fills table game name or poker structure from the last session of that type.
    private func applyLastSavedGameDefaults() {
        if gameCategory == .table {
            if !settingsStore.lastTableGameName.isEmpty {
                selectedGame = settingsStore.lastTableGameName
            }
            return
        }
        if gameCategory == .slots {
            if !settingsStore.lastSlotGameName.isEmpty {
                selectedGame = settingsStore.lastSlotGameName
            }
            if let d = settingsStore.lastSlotSessionDefaults {
                slotNotes = d.slotNotes
            } else {
                slotNotes = ""
            }
            return
        }
        guard let d = settingsStore.lastPokerSessionDefaults else { return }
        pokerGameKind = d.pokerGameKind
        pokerAllowsRebuy = d.pokerAllowsRebuy
        pokerAllowsAddOn = d.pokerAllowsAddOn
        pokerHasFreezeOut = d.pokerHasFreezeOut
        pokerVariant = d.pokerVariant
        pokerSmallBlind = d.pokerSmallBlind
        pokerBigBlind = d.pokerBigBlind
        pokerAnte = d.pokerAnte
        pokerLevelMinutesText = d.pokerLevelMinutesText
        pokerStartingStackText = d.pokerStartingStackText
        pokerTournamentCostText = d.pokerTournamentCostText
    }

    private func attemptGo() {
        if needsTierTrackingWarning {
            showTierTrackingWarning = true
        } else {
            go(skipTierTrackingWarning: true)
        }
    }

    func go(skipTierTrackingWarning: Bool = false) {
        if gameCategory == .poker {
            selectedGame = FastCheckInHelper.composedPokerGameName(
                pokerGameKind: pokerGameKind,
                pokerVariant: pokerVariant,
                pokerAllowsRebuy: pokerAllowsRebuy,
                pokerAllowsAddOn: pokerAllowsAddOn,
                pokerHasFreezeOut: pokerHasFreezeOut
            )
        }

        if !skipTierTrackingWarning && needsTierTrackingWarning {
            showTierTrackingWarning = true
            return
        }

        guard let buy = Int(initialBuyIn), buy > 0 else { return }
        let trimmedTier = startingTier.trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = trimmedTier.isEmpty ? 0 : (Int(trimmedTier) ?? 0)
        let program = selectedRewardsProgram.trimmingCharacters(in: .whitespacesAndNewlines)
        store.startSession(
            game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: buy,
            rewardsProgramName: program.isEmpty ? nil : program,
            casinoLatitude: casinoLatitude,
            casinoLongitude: casinoLongitude
        )
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
        let slotMeta = Session.persistedSlotMetadata(
            gameCategory: gameCategory,
            format: nil,
            formatOther: "",
            feature: nil,
            featureOther: "",
            notes: slotNotes
        )
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
            pokerStartingStack: startingStack,
            slotFormat: slotMeta.format,
            slotFormatOther: slotMeta.formatOther,
            slotFeature: slotMeta.feature,
            slotFeatureOther: slotMeta.featureOther,
            slotNotes: slotMeta.notes
        )
        settingsStore.recordLastCheckInGameSelection(
            gameCategory: gameCategory,
            selectedGame: selectedGame,
            pokerGameKind: pokerGameKind,
            pokerAllowsRebuy: pokerAllowsRebuy,
            pokerAllowsAddOn: pokerAllowsAddOn,
            pokerHasFreezeOut: pokerHasFreezeOut,
            pokerVariant: pokerVariant,
            pokerSmallBlind: pokerSmallBlind,
            pokerBigBlind: pokerBigBlind,
            pokerAnte: pokerAnte,
            pokerLevelMinutesText: pokerLevelMinutesText,
            pokerStartingStackText: pokerStartingStackText,
            pokerTournamentCostText: pokerTournamentCostText,
            slotNotes: slotMeta.notes ?? ""
        )
        if settingsStore.enableCasinoFeedback {
            CelebrationPlayer.shared.playQuickChime()
        }
        dismiss()
    }
}
