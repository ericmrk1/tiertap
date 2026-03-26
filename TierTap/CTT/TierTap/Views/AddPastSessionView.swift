import SwiftUI

struct AddPastSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var isCasinoPublic = true
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var totalBuyIn = ""
    @State private var cashOut = ""
    @State private var startingTier = "0"
    @State private var endingTier = ""
    @State private var avgBetActual = ""
    @State private var avgBetRated = ""
    @State private var selectedRewardsProgram = ""

    @State private var showGamePicker = false
    @State private var showCasinoLocationPicker = false
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

    @State private var casinoLatitude: Double?
    @State private var casinoLongitude: Double?

    /// Games to show as main grid: favorites only; fallback to pinned if no favorites set.
    private var displayGames: [String] {
        if !settingsStore.favoriteGames.isEmpty { return settingsStore.favoriteGames }
        return GamesList.pinned
    }

    private var displaySlots: [String] {
        if !settingsStore.favoriteSlotGames.isEmpty { return settingsStore.favoriteSlotGames }
        return SlotsList.pinned
    }

    private var activeGameGridTitles: [String] {
        switch gameCategory {
        case .table: return displayGames
        case .slots: return displaySlots
        case .poker: return []
        }
    }

    private var isGameInDisplayList: Bool {
        let list = gameCategory == .slots ? displaySlots : displayGames
        return selectedGame.isEmpty || list.contains(selectedGame)
    }

    private var buyInGridAmounts: [Int] {
        let base = settingsStore.effectiveDenominations
        let denoms = base.isEmpty ? [100, 200, 300, 500, 1000, 2000, 5000, 10_000] : base
        var set: Set<Int> = Set(denoms)

        for d in denoms {
            set.insert(d)
            set.insert(d * 2)
            set.insert(d * 3)
            if d >= 100 { set.insert(d / 2) }
        }

        set.insert(25); set.insert(50); set.insert(75); set.insert(150); set.insert(250); set.insert(750)

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
        let buyOK = (Int(totalBuyIn) ?? 0) > 0
        return hasGame && !casino.isEmpty &&
            endTime > startTime &&
            buyOK && Int(cashOut) != nil &&
            Int(startingTier) != nil && Int(endingTier) != nil &&
            Int(avgBetActual) != nil && Int(avgBetRated) != nil
    }

    private let blindPickerValues: [Int] = [0, 1, 2, 3, 5, 10, 20, 40, 80, 100, 200, 300, 400, 500, 600, 800, 1000]

    /// Quick denominations pulled from Settings, falling back to sensible defaults.
    private var quickDenominations: [Int] {
        let base = settingsStore.effectiveDenominations
        return base.isEmpty ? [20, 100, 500, 1000, 10_000] : base
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        gameSection
                        casinoAndTimeSection
                        startingTierSection
                        totalBuyInSection
                        endingTierSection
                        moneyAndBetsSection
                        saveButton
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Past Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .adaptiveSheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame, mode: gameCategory == .slots ? .slots : .table)
                    .environmentObject(settingsStore)
                    .gamePickerSheetPresentation()
            }
            .fullScreenCover(isPresented: $showCasinoLocationPicker) {
                NavigationStack {
                    CasinoLocationPickerView(selectedCasino: $casino, selectedLatitude: $casinoLatitude, selectedLongitude: $casinoLongitude)
                        .environmentObject(settingsStore)
                }
            }
            .adaptiveSheet(isPresented: $showBuyInPicker) {
                BuyInGridSheet(amounts: buyInGridAmounts, selected: $totalBuyIn)
                    .environmentObject(settingsStore)
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: selectedGame) { newGame in
                guard !newGame.isEmpty else { return }
                let defaults = store.defaultAvgBets(for: newGame)
                if avgBetActual.isEmpty, let a = defaults.actual {
                    avgBetActual = "\(a)"
                }
                if avgBetRated.isEmpty, let r = defaults.rated {
                    avgBetRated = "\(r)"
                }
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

    private func applyCasinoHistoryDefaults() {
        guard store.hasSessionHistory(forExactCasino: casino) else { return }
        if let tier = store.defaultEndingTierPoints(for: casino) {
            startingTier = "\(tier)"
        }
        if let buy = store.defaultInitialBuyIn(for: casino) {
            totalBuyIn = "\(buy)"
        }
    }

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

    @ViewBuilder private var gameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Casino Game", systemImage: "suit.club.fill")
                .font(.headline).foregroundColor(.white)

            GameCategoryWheelPicker(selection: $gameCategory, heading: "Game Type")
                .environmentObject(settingsStore)

            if gameCategory == .table || gameCategory == .slots {
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
                VStack(alignment: .leading, spacing: 12) {
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
                                blindPresetButton("$1/$2", sb: 1, bb: 2, ante: 0)
                                blindPresetButton("$1/$3", sb: 1, bb: 3, ante: 0)
                                blindPresetButton("$2/$5", sb: 2, bb: 5, ante: 0)
                                blindPresetButton("$5/$10", sb: 5, bb: 10, ante: 0)
                                blindPresetButton("$10/$20", sb: 10, bb: 20, ante: 0)
                                blindPresetButton("$20/$40", sb: 20, bb: 40, ante: 0)
                                blindPresetButton("$40/$80", sb: 40, bb: 80, ante: 0)
                                blindPresetButton("$100/$200", sb: 100, bb: 200, ante: 0)
                                blindPresetButton("$200/$400", sb: 200, bb: 400, ante: 0)
                                blindPresetButton("$300/$600", sb: 300, bb: 600, ante: 0)
                                blindPresetButton("$400/$800", sb: 400, bb: 800, ante: 0)
                                blindPresetButton("$500/$1000", sb: 500, bb: 1000, ante: 0)
                                blindPresetButton("$1/$3/$5", sb: 1, bb: 3, ante: 5)
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
    }

    private func blindPresetButton(_ title: String, sb: Int, bb: Int, ante: Int) -> some View {
        Button(title) {
            pokerSmallBlind = sb
            pokerBigBlind = bb
            pokerAnte = ante
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.35))
        .foregroundColor(.white)
        .cornerRadius(8)
    }

    @ViewBuilder private var casinoAndTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .colorScheme(.dark)
            HStack(spacing: 12) {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    @ViewBuilder private var startingTierSection: some View {
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
                    .font(.caption)
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
    }

    @ViewBuilder private var totalBuyInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Total Buy-In", systemImage: "dollarsign.circle")
                .font(.headline).foregroundColor(.white)
            HStack(alignment: .top, spacing: 12) {
                Button { showBuyInPicker = true } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2.fill")
                        Text(totalBuyIn.isEmpty ? "Choose cash" : "\(settingsStore.currencySymbol)\(totalBuyIn)")
                            .lineLimit(1)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Exact amount", text: $totalBuyIn)
                        .textFieldStyle(DarkTextFieldStyle())
                        .keyboardType(.numberPad)
                }
                .frame(maxWidth: .infinity)
            }
            if settingsStore.unitSize > 0, (Int(totalBuyIn) ?? 0) > settingsStore.unitSize {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Buy-in (\(settingsStore.currencySymbol)\(totalBuyIn)) exceeds your unit size (\(settingsStore.currencySymbol)\(settingsStore.unitSize)). Consider lowering to stay within bankroll target.")
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
    }

    @ViewBuilder private var endingTierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ending Tier Points", systemImage: "star.circle.fill")
                .font(.headline)
                .foregroundColor(.white)
            Text("Use wheel or type exact.")
                .font(.caption).foregroundColor(.gray)
            HStack(spacing: 12) {
                TierPointsWheel(selectedValue: $endingTier)
                    .frame(maxWidth: .infinity)
                TextField("Exact value", text: $endingTier)
                    .textFieldStyle(DarkTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(width: 110)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

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

    @ViewBuilder private var moneyAndBetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cash Out & Avg Bets")
                .font(.headline)
                .foregroundColor(.white)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    compactNumberField(label: "Cash Out (\(settingsStore.currencySymbol))", placeholder: "Amount cashed out", text: $cashOut)
                }
                GridRow {
                    compactNumberField(label: "Avg Bet Actual (\(settingsStore.currencySymbol))", placeholder: "Actual avg bet", text: $avgBetActual)
                    compactNumberField(label: "Avg Bet Rated (\(settingsStore.currencySymbol))", placeholder: "Rated avg bet", text: $avgBetRated)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Common amounts").font(.caption.bold()).foregroundColor(.gray)
                CommonAmountButtons(amounts: quickDenominations, selected: $avgBetActual)
                CommonAmountButtons(amounts: quickDenominations, selected: $avgBetRated)
            }
            quickAddButtons
            unitSizeWarning
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    @ViewBuilder private var quickAddButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick add amounts")
                .font(.caption.bold())
                .foregroundColor(.gray)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickDenominations, id: \.self) { amt in
                        Button("+\(settingsStore.currencySymbol)\(amt)") {
                            let current = Int(totalBuyIn) ?? 0
                            totalBuyIn = String(current + amt)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickDenominations, id: \.self) { amt in
                        Button("+\(settingsStore.currencySymbol)\(amt) cash out") {
                            let current = Int(cashOut) ?? 0
                            cashOut = String(current + amt)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    @ViewBuilder private var unitSizeWarning: some View {
        if settingsStore.unitSize > 0,
           (Int(cashOut) ?? 0) > settingsStore.unitSize ||
           (Int(avgBetActual) ?? 0) > settingsStore.unitSize ||
           (Int(avgBetRated) ?? 0) > settingsStore.unitSize {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Cash out or bet exceeds unit size (\(settingsStore.currencySymbol)\(settingsStore.unitSize)). Set unit in Settings to match your bankroll plan.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)
        }
    }

    @ViewBuilder private var saveButton: some View {
        Button { save() } label: {
            Text("Save Session")
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
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
    }

    private func compactNumberField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
            TextField(placeholder, text: text)
                .textFieldStyle(DarkTextFieldStyle())
                .keyboardType(.numberPad)
        }
    }

    func save() {
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

        guard let bi = Int(totalBuyIn), let co = Int(cashOut),
              let st = Int(startingTier), let et = Int(endingTier),
              let aba = Int(avgBetActual), let abr = Int(avgBetRated) else { return }
        let program = selectedRewardsProgram.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        let dc = cal.dateComponents([.year,.month,.day], from: date)
        let sc = cal.dateComponents([.hour,.minute], from: startTime)
        let ec = cal.dateComponents([.hour,.minute], from: endTime)
        var s1 = DateComponents(); s1.year=dc.year; s1.month=dc.month; s1.day=dc.day; s1.hour=sc.hour; s1.minute=sc.minute
        var e1 = DateComponents(); e1.year=dc.year; e1.month=dc.month; e1.day=dc.day; e1.hour=ec.hour; e1.minute=ec.minute
        let start = cal.date(from: s1) ?? date
        let end = cal.date(from: e1) ?? date.addingTimeInterval(3600)
        let ev = BuyInEvent(amount: bi, timestamp: start)
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
        let session = Session(
            game: selectedGame,
            casino: casino,
            casinoLatitude: casinoLatitude,
            casinoLongitude: casinoLongitude,
            startTime: start,
            endTime: end,
            startingTierPoints: st,
            endingTierPoints: et,
            buyInEvents: [ev],
            cashOut: co,
            avgBetActual: aba,
            avgBetRated: abr,
            isLive: false,
            status: .complete,
            sessionMood: nil,
            privateNotes: nil,
            rewardsProgramName: program.isEmpty ? nil : program,
            chipEstimatorImageFilename: nil,
            gameCategory: gameCategory,
            pokerGameKind: gameCategory == .poker ? pokerGameKind : nil,
            pokerAllowsRebuy: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsRebuy : nil,
            pokerAllowsAddOn: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsAddOn : nil,
            pokerHasFreeOut: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerHasFreezeOut : nil,
            pokerVariant: gameCategory == .poker ? pokerVariant : nil,
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
        store.addPastSession(session)
        dismiss()
    }
}
