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

    @State private var showGamePicker = false
    @State private var showCasinoPicker = false

    var isValid: Bool {
        !selectedGame.isEmpty && !casino.isEmpty &&
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
            .sheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame)
                    .environmentObject(settingsStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCasinoPicker) {
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
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
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
        let session = Session(game: selectedGame, casino: casino,
            startTime: start, endTime: end, startingTierPoints: st,
            endingTierPoints: et, buyInEvents: [ev], cashOut: co,
            avgBetActual: aba, avgBetRated: abr, isLive: false)
        store.addPastSession(session)
        dismiss()
    }
}
