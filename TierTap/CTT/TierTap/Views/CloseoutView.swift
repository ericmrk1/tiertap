import SwiftUI

struct CloseoutView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var cashOut = ""
    @State private var avgBetActual = ""
    @State private var avgBetRated = ""
    @State private var endingTier = ""
    @State private var showLowAlert = false
    @State private var showCelebration = false
    @State private var showEmotionPicker = false
    @State private var closedSessionId: UUID?
    @State private var showGASheet = false
    @State private var privateNotes = ""

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    /// Quick denominations for adjusting cash-out, falling back to sensible defaults.
    private var cashOutQuickAmounts: [Int] {
        let base = settingsStore.effectiveDenominations
        return base.isEmpty ? [25, 50, 100, 200, 500, 1000] : base
    }

    var isValid: Bool {
        Int(cashOut) != nil && Int(avgBetActual) != nil &&
        Int(avgBetRated) != nil && Int(endingTier) != nil
    }

    var previewTierEarned: Int? { Int(endingTier).map { $0 - s.startingTierPoints } }
    var previewHours: Double { s.hoursPlayed }
    var previewTPH: Double? {
        guard let e = previewTierEarned, previewHours > 0 else { return nil }
        return Double(e) / previewHours
    }
    var previewWL: Int? { Int(cashOut).map { $0 - s.totalBuyIn } }
    var previewT100: Double? {
        guard let r = Int(avgBetRated), r >= 100,
              let e = previewTierEarned, previewHours > 0 else { return nil }
        return (Double(e) / (Double(r) * previewHours)) * 100
    }

    var timerStopped: Bool { s.endTime != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if showCelebration {
                    ConfettiCelebrationView()
                }
                ScrollView {
                    VStack(spacing: 12) {
                        // Top: Stop/Resume Timer primary button + compact header (one line)
                        VStack(spacing: 8) {
                            Button {
                                if timerStopped {
                                    store.resumeLiveSessionTimer()
                                } else {
                                    store.stopLiveSessionTimer()
                                }
                            } label: {
                                Label(timerStopped ? "Resume Timer" : "Stop Timer",
                                      systemImage: timerStopped ? "play.circle.fill" : "stop.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(timerStopped ? Color.green : Color.red)
                                    .foregroundColor(timerStopped ? .black : .white)
                                    .cornerRadius(12)
                            }

                            HStack {
                                if timerStopped {
                                    Label("Timer stopped", systemImage: "stop.circle.fill")
                                        .font(.caption).foregroundColor(.orange)
                                } else {
                                    Label("Timer running", systemImage: "play.circle.fill")
                                        .font(.caption).foregroundColor(.green)
                                }
                                Spacer()
                                Text(s.casino).font(.subheadline.bold()).foregroundColor(.white)
                                Text("·").foregroundColor(.gray)
                                Text(Session.durationString(s.duration)).font(.caption.monospacedDigit()).foregroundColor(.green)
                                Text("·").foregroundColor(.gray)
                                Text("\(settingsStore.currencySymbol)\(s.totalBuyIn)").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(12)
                        }

                        // Inputs (compact)
                        VStack(spacing: 8) {
                            InputRow(label: "Cash Out (\(settingsStore.currencySymbol))", placeholder: "Amount leaving with", value: $cashOut)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Adjust cash out")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(cashOutQuickAmounts, id: \.self) { amt in
                                            Button("+\(settingsStore.currencySymbol)\(amt)") {
                                                let current = Int(cashOut) ?? s.totalBuyIn
                                                cashOut = String(current + amt)
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
                                        ForEach(cashOutQuickAmounts, id: \.self) { amt in
                                            Button("−\(settingsStore.currencySymbol)\(amt)") {
                                                let current = Int(cashOut) ?? s.totalBuyIn
                                                cashOut = String(max(0, current - amt))
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
                                HStack(spacing: 8) {
                                    Button("Lost everything") {
                                        cashOut = "0"
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.25))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)

                                    Button("Double or nothing") {
                                        cashOut = String(s.totalBuyIn * 2)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)

                                    Button("Triple") {
                                        cashOut = String(s.totalBuyIn * 3)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                            InputRow(label: "Avg Bet Actual (\(settingsStore.currencySymbol))", placeholder: "Actual avg bet", value: $avgBetActual)
                            CommonAmountButtons(amounts: settingsStore.effectiveDenominations.isEmpty ? [25, 50, 100, 200, 500, 1000] : settingsStore.effectiveDenominations, selected: $avgBetActual)
                            InputRow(label: "Avg Bet Rated (\(settingsStore.currencySymbol))", placeholder: "Rated avg bet", value: $avgBetRated)
                            CommonAmountButtons(amounts: settingsStore.effectiveDenominations.isEmpty ? [25, 50, 100, 200, 500, 1000] : settingsStore.effectiveDenominations, selected: $avgBetRated)
                            InputRow(label: "Ending Tier Points", placeholder: "Loyalty app now", value: $endingTier)
                            if settingsStore.unitSize > 0,
                               (Int(avgBetActual) ?? 0) > settingsStore.unitSize || (Int(avgBetRated) ?? 0) > settingsStore.unitSize || s.totalBuyIn > settingsStore.unitSize {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption2)
                                    Text("Exceeds unit \(settingsStore.currencySymbol)\(settingsStore.unitSize).").font(.caption2).foregroundColor(.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(6)
                            }
                        }

                        // Summary inline when valid (compact)
                        if isValid {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let wl = previewWL {
                                        Text("W/L").font(.caption2).foregroundColor(.gray)
                                        Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                            .font(.subheadline.bold())
                                            .foregroundColor(wl >= 0 ? .green : .red)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Buy-in").font(.caption2).foregroundColor(.gray)
                                    Text("\(settingsStore.currencySymbol)\(s.totalBuyIn)").font(.subheadline).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hrs").font(.caption2).foregroundColor(.gray)
                                    Text(String(format: "%.2f", previewHours)).font(.subheadline).foregroundColor(.white)
                                }
                                if let e = previewTierEarned {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Pts").font(.caption2).foregroundColor(.gray)
                                        Text("\(e >= 0 ? "+" : "")\(e)").font(.subheadline).foregroundColor(e >= 0 ? .green : .orange)
                                    }
                                }
                                if let t = previewTPH {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Pts/hr").font(.caption2).foregroundColor(.gray)
                                        Text(String(format: "%.1f", t)).font(.subheadline).foregroundColor(.white)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(12)

                                if let wl = previewWL,
                                   let abet = Int(avgBetActual), abet > 0,
                                   let result = StrategyDatabase.expectedLossAndAboveEdge(gameName: s.game, winLoss: wl, avgBet: abet, hours: previewHours) {
                                let above = result.aboveEdge >= 0
                                let amount = Int(round(abs(result.aboveEdge)))
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.caption)
                                        .foregroundColor(above ? .green : .orange)
                                    Text(above ? "\(settingsStore.currencySymbol)\(amount) above statistical house edge" : "\(settingsStore.currencySymbol)\(amount) below statistical house edge")
                                        .font(.caption)
                                        .foregroundColor(above ? .green : .orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.systemGray6).opacity(0.12))
                                .cornerRadius(10)
                            }
                        }

                        // Private notes (local only, not shared)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private notes (not shared)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            TextEditor(text: $privateNotes)
                                .frame(minHeight: 72)
                                .padding(8)
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .scrollContentBackground(.hidden)
                        }

                        // Actions
                        VStack(spacing: 8) {
                            Button {
                                if let et = Int(endingTier), et < s.startingTierPoints {
                                    showLowAlert = true
                                } else { save() }
                            } label: {
                                Text("Save Session")
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(isValid ? Color.green : Color.gray)
                                    .foregroundColor(isValid ? .black : .white)
                                    .cornerRadius(12).font(.headline)
                            }
                            .disabled(!isValid)

                            Button { dismiss() } label: {
                                Text("Cancel — Return to Session")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Tier Points Decreased", isPresented: $showLowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") { save() }
            } message: {
                Text("Ending tier (\(endingTier)) is lower than starting tier (\(s.startingTierPoints)). Save anyway?")
            }
            .sheet(isPresented: $showEmotionPicker, onDismiss: {
                if closedSessionId != nil, let co = Int(cashOut), let aba = Int(avgBetActual),
                   let abr = Int(avgBetRated), let et = Int(endingTier) {
                    let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    store.closeSession(cashOut: co, avgBetActual: aba, avgBetRated: abr, endingTier: et, privateNotes: notes)
                    closedSessionId = nil
                    dismiss()
                }
            }) {
                SessionMoodPickerView { mood in
                    guard let co = Int(cashOut), let aba = Int(avgBetActual),
                          let abr = Int(avgBetRated), let et = Int(endingTier),
                          let id = closedSessionId else {
                        closedSessionId = nil
                        dismiss()
                        return
                    }
                    let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
                    store.closeSession(cashOut: co, avgBetActual: aba, avgBetRated: abr, endingTier: et, privateNotes: notes)
                    if var session = store.sessions.first(where: { $0.id == id }) {
                        session.sessionMood = mood
                        store.updateSession(session)
                    }
                    closedSessionId = nil
                    if store.recentMoodDownswingDetected() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showGASheet = true
                        }
                    }
                    dismiss()
                }
                .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showGASheet) {
                GASupportSheet(onDismiss: {
                    showGASheet = false
                    dismiss()
                })
                .environmentObject(settingsStore)
            }
        }
        .onAppear {
            privateNotes = s.privateNotes ?? ""
            if cashOut.isEmpty {
                cashOut = "\(s.totalBuyIn)"
            }
            // Default ending tier to this session's starting tier if available,
            // falling back to recent history for this casino.
            if endingTier.isEmpty {
                if s.startingTierPoints > 0 {
                    endingTier = "\(s.startingTierPoints)"
                } else if let hist = store.defaultEndingTierPoints(for: s.casino) {
                    endingTier = "\(hist)"
                }
            }
            // Pre-populate avg bets based on recent history for this game.
            if avgBetActual.isEmpty || avgBetRated.isEmpty {
                let defaults = store.defaultAvgBets(for: s.game)
                if avgBetActual.isEmpty, let a = defaults.actual {
                    avgBetActual = "\(a)"
                }
                if avgBetRated.isEmpty, let r = defaults.rated {
                    avgBetRated = "\(r)"
                }
            }
        }
    }

    func save() {
        guard let co = Int(cashOut), let aba = Int(avgBetActual),
              let abr = Int(avgBetRated), let et = Int(endingTier) else { return }
        let sessionId = s.id
        let netPositive = (co - s.totalBuyIn) > 0

        let notes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : privateNotes
        if !settingsStore.promptSessionMood {
            if netPositive {
                CelebrationPlayer.shared.celebrateWin()
                showCelebration = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    store.closeSession(cashOut: co, avgBetActual: aba, avgBetRated: abr, endingTier: et, privateNotes: notes)
                    dismiss()
                }
            } else {
                store.closeSession(cashOut: co, avgBetActual: aba, avgBetRated: abr, endingTier: et, privateNotes: notes)
                dismiss()
            }
            return
        }

        if netPositive {
            CelebrationPlayer.shared.celebrateWin()
            showCelebration = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                closedSessionId = sessionId
                showEmotionPicker = true
            }
        } else {
            closedSessionId = sessionId
            showEmotionPicker = true
        }
    }
}
