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

    var isValid: Bool {
        !selectedGame.isEmpty && !casino.isEmpty &&
        endTime > startTime &&
        Int(totalBuyIn) != nil && Int(cashOut) != nil &&
        Int(startingTier) != nil && Int(endingTier) != nil &&
        Int(avgBetActual) != nil && Int(avgBetRated) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Game
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

                        // Casino + Time
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Casino").font(.subheadline.bold()).foregroundColor(.white)
                                TextField("Casino name", text: $casino).textFieldStyle(DarkTextFieldStyle())
                            }
                            DatePicker("Date", selection: $date, displayedComponents: .date).colorScheme(.dark)
                            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute).colorScheme(.dark)
                            DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute).colorScheme(.dark)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Financial
                        VStack(spacing: 12) {
                            Text("Financial").font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            InputRow(label: "Total Buy-In ($)", placeholder: "Total bought in", value: $totalBuyIn)
                            InputRow(label: "Cash Out ($)", placeholder: "Amount cashed out", value: $cashOut)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Tier Points
                        VStack(spacing: 12) {
                            Text("Tier Points").font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            InputRow(label: "Starting Tier Points", placeholder: "Points at session start", value: $startingTier)
                            InputRow(label: "Ending Tier Points", placeholder: "Points at session end", value: $endingTier)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Bets
                        VStack(spacing: 12) {
                            Text("Average Bets").font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            InputRow(label: "Avg Bet Actual ($)", placeholder: "Actual average bet", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated ($)", placeholder: "Rated average bet", value: $avgBetRated)
                            if settingsStore.unitSize > 0,
                               (Int(totalBuyIn) ?? 0) > settingsStore.unitSize || (Int(avgBetActual) ?? 0) > settingsStore.unitSize || (Int(avgBetRated) ?? 0) > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Buy-in or bet exceeds unit size ($\(settingsStore.unitSize)). Set unit in Settings to match your bankroll plan.")
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

                        Button { save() } label: {
                            Text("Save Session")
                                .frame(maxWidth: .infinity).padding()
                                .background(isValid ? Color.green : Color.gray)
                                .foregroundColor(isValid ? .black : .white)
                                .cornerRadius(14).font(.headline)
                        }
                        .disabled(!isValid)
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Past Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame).presentationDetents([.medium, .large])
            }
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
