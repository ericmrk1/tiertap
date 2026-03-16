import SwiftUI

struct AddPastSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var totalBuyIn = ""
    @State private var cashOut = ""
    @State private var startingTier = ""
    @State private var endingTier = ""
    @State private var avgBetActual = ""
    @State private var avgBetRated = ""

    // Casino game type metadata
    @State private var gameCategory: SessionGameCategory = .table
    @State private var pokerGameKind: SessionPokerGameKind = .cash
    @State private var pokerAllowsRebuy: Bool = false
    @State private var pokerAllowsAddOn: Bool = false
    @State private var pokerHasFreeOut: Bool = false
    @State private var pokerVariant: String = "No Limit Texas Hold’em"
    @State private var pokerSmallBlindText: String = ""
    @State private var pokerBigBlindText: String = ""
    @State private var pokerAnteText: String = ""
    @State private var pokerLevelMinutesText: String = ""
    @State private var pokerStartingStackText: String = ""

    @State private var showGamePicker = false
    @State private var showCasinoPicker = false

    var isValid: Bool {
        let hasGame: Bool = (gameCategory == .poker) ? true : !selectedGame.isEmpty
        return hasGame && !casino.isEmpty &&
        endTime > startTime &&
        Int(totalBuyIn) != nil && Int(cashOut) != nil &&
        Int(startingTier) != nil && Int(endingTier) != nil &&
        Int(avgBetActual) != nil && Int(avgBetRated) != nil
    }

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
                        moneyAndBetsSection
                        tierPointsSection
                        saveButton
                    }
                    .padding()
                }
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
                GamePickerView(selectedGame: $selectedGame)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .adaptiveSheet(isPresented: $showCasinoPicker) {
                CasinoLocationPickerView(selectedCasino: $casino)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedGame) { newGame in
                guard !newGame.isEmpty else { return }
                // Try to pre-populate avg bets from history for this game.
                let defaults = store.defaultAvgBets(for: newGame)
                if avgBetActual.isEmpty, let a = defaults.actual {
                    avgBetActual = "\(a)"
                }
                if avgBetRated.isEmpty, let r = defaults.rated {
                    avgBetRated = "\(r)"
                }
            }
        }
    }

    @ViewBuilder private var gameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Casino Game", systemImage: "suit.club.fill")
                .font(.headline).foregroundColor(.white)

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

            if gameCategory == .table {
                Button { showGamePicker = true } label: {
                    HStack {
                        Text(selectedGame.isEmpty ? "Select game..." : selectedGame)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(selectedGame.isEmpty ? .gray : .white)
                    .cornerRadius(10)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        GameTypePill(title: "Cash", isSelected: pokerGameKind == .cash) {
                            pokerGameKind = .cash
                        }
                        GameTypePill(title: "Tournament", isSelected: pokerGameKind == .tournament) {
                            pokerGameKind = .tournament
                        }
                    }

                    if pokerGameKind == .tournament {
                        HStack(spacing: 8) {
                            OptionChip(title: "Re-buy", isOn: pokerAllowsRebuy) {
                                pokerAllowsRebuy.toggle()
                            }
                            OptionChip(title: "Add-On", isOn: pokerAllowsAddOn) {
                                pokerAllowsAddOn.toggle()
                            }
                            OptionChip(title: "Free-Out", isOn: pokerHasFreeOut) {
                                pokerHasFreeOut.toggle()
                            }
                        }
                    }

                    Picker("Poker Type", selection: $pokerVariant) {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blinds & Structure")
                            .font(.caption.bold())
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            TextField("SB", text: $pokerSmallBlindText)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                            TextField("BB", text: $pokerBigBlindText)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                            TextField("Ante", text: $pokerAnteText)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                        }

                        if pokerGameKind == .tournament {
                            HStack(spacing: 8) {
                                TextField("Level mins", text: $pokerLevelMinutesText)
                                    .textFieldStyle(DarkTextFieldStyle())
                                    .keyboardType(.numberPad)
                                TextField("Starting stack", text: $pokerStartingStackText)
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

    @ViewBuilder private var casinoAndTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Casino").font(.subheadline.bold()).foregroundColor(.white)
                TextField("Casino name", text: $casino)
                    .textFieldStyle(DarkTextFieldStyle())
                favoriteCasinosButtons
                Button {
                    showCasinoPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Choose from nearby casinos & favorites")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.top, 4)
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

    @ViewBuilder private var favoriteCasinosButtons: some View {
        if !settingsStore.favoriteCasinos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(settingsStore.favoriteCasinos, id: \.self) { name in
                        Button(name) {
                            casino = name
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(casino == name ? Color.green : Color(.systemGray6).opacity(0.25))
                        .foregroundColor(casino == name ? .black : .white)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var moneyAndBetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Money & Bets")
                .font(.headline)
                .foregroundColor(.white)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    compactNumberField(label: "Total Buy-In (\(settingsStore.currencySymbol))", placeholder: "Total bought in", text: $totalBuyIn)
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
           (Int(totalBuyIn) ?? 0) > settingsStore.unitSize ||
           (Int(avgBetActual) ?? 0) > settingsStore.unitSize ||
           (Int(avgBetRated) ?? 0) > settingsStore.unitSize {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Buy-in or bet exceeds unit size (\(settingsStore.currencySymbol)\(settingsStore.unitSize)). Set unit in Settings to match your bankroll plan.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)
        }
    }

    @ViewBuilder private var tierPointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tier Points")
                .font(.headline)
                .foregroundColor(.white)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    compactNumberField(label: "Starting Tier Points", placeholder: "At session start", text: $startingTier)
                    compactNumberField(label: "Ending Tier Points", placeholder: "At session end", text: $endingTier)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var saveButton: some View {
        Button { save() } label: {
            Text("Save Session")
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValid ? Color.green : Color.gray)
                .foregroundColor(isValid ? .black : .white)
                .cornerRadius(14)
                .font(.headline)
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
                if pokerHasFreeOut { opts.append("Free-Out") }
                if !opts.isEmpty {
                    parts.append(opts.joined(separator: ", "))
                }
            }
            selectedGame = parts.joined(separator: " - ")
        }

        guard let bi = Int(totalBuyIn), let co = Int(cashOut),
              let st = Int(startingTier), let et = Int(endingTier),
              let aba = Int(avgBetActual), let abr = Int(avgBetRated) else { return }
        let cal = Calendar.current
        let dc = cal.dateComponents([.year,.month,.day], from: date)
        let sc = cal.dateComponents([.hour,.minute], from: startTime)
        let ec = cal.dateComponents([.hour,.minute], from: endTime)
        var s1 = DateComponents(); s1.year=dc.year; s1.month=dc.month; s1.day=dc.day; s1.hour=sc.hour; s1.minute=sc.minute
        var e1 = DateComponents(); e1.year=dc.year; e1.month=dc.month; e1.day=dc.day; e1.hour=ec.hour; e1.minute=ec.minute
        let start = cal.date(from: s1) ?? date
        let end = cal.date(from: e1) ?? date.addingTimeInterval(3600)
        let ev = BuyInEvent(amount: bi, timestamp: start)
        let sb: Int? = (gameCategory == .poker) ? Int(pokerSmallBlindText) : nil
        let bb: Int? = (gameCategory == .poker) ? Int(pokerBigBlindText) : nil
        let ante: Int? = (gameCategory == .poker) ? Int(pokerAnteText) : nil
        let levelMinutes: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerLevelMinutesText) : nil
        let startingStack: Int? = (gameCategory == .poker && pokerGameKind == .tournament) ? Int(pokerStartingStackText) : nil
        let session = Session(
            game: selectedGame,
            casino: casino,
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
            chipEstimatorImageFilename: nil,
            gameCategory: gameCategory,
            pokerGameKind: gameCategory == .poker ? pokerGameKind : nil,
            pokerAllowsRebuy: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsRebuy : nil,
            pokerAllowsAddOn: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerAllowsAddOn : nil,
            pokerHasFreeOut: (gameCategory == .poker && pokerGameKind == .tournament) ? pokerHasFreeOut : nil,
            pokerVariant: gameCategory == .poker ? pokerVariant : nil,
            pokerSmallBlind: sb,
            pokerBigBlind: bb,
            pokerAnte: ante,
            pokerLevelMinutes: levelMinutes,
            pokerStartingStack: startingStack
        )
        store.addPastSession(session)
        dismiss()
    }
}
