import SwiftUI

/// Fill in missing closeout details for a session that was cashed out from Watch (requiring more info).
struct CompleteSessionView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var cashOut: String = ""
    @State private var avgBetActual = ""
    @State private var avgBetRated = ""
    @State private var endingTier = ""
    @State private var showLowAlert = false
    @State private var showCelebration = false

    init(session: Session) {
        self.session = session
    }

    var isValid: Bool {
        Int(cashOut) != nil && Int(avgBetActual) != nil &&
        Int(avgBetRated) != nil && Int(endingTier) != nil
    }

    var previewTierEarned: Int? { Int(endingTier).map { $0 - session.startingTierPoints } }
    var previewHours: Double { session.hoursPlayed }
    var previewTPH: Double? {
        guard let e = previewTierEarned, previewHours > 0 else { return nil }
        return Double(e) / previewHours
    }
    var previewWL: Int? { Int(cashOut).map { $0 - session.totalBuyIn } }
    var previewT100: Double? {
        guard let r = Int(avgBetRated), r >= 100,
              let e = previewTierEarned, previewHours > 0 else { return nil }
        return (Double(e) / (Double(r) * previewHours)) * 100
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if showCelebration {
                    ConfettiCelebrationView()
                }
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 6) {
                            Text(session.casino).font(.title2.bold()).foregroundColor(.white)
                            Text(session.game).foregroundColor(.gray)
                            HStack(spacing: 16) {
                                Label(Session.durationString(session.duration), systemImage: "clock")
                                Label("Buy-in: $\(session.totalBuyIn)", systemImage: "dollarsign.circle")
                            }
                            .font(.caption).foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        VStack(spacing: 14) {
                            InputRow(label: "Cash Out ($)", placeholder: "Amount left with", value: $cashOut)
                            InputRow(label: "Avg Bet Actual ($)", placeholder: "Actual avg bet", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated ($)", placeholder: "Rated avg bet", value: $avgBetRated)
                            InputRow(label: "Ending Tier Points", placeholder: "From loyalty app", value: $endingTier)
                            if settingsStore.unitSize > 0,
                               (Int(avgBetActual) ?? 0) > settingsStore.unitSize || (Int(avgBetRated) ?? 0) > settingsStore.unitSize || session.totalBuyIn > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Bet or buy-in exceeds unit size ($\(settingsStore.unitSize)).")
                                        .font(.caption).foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }

                        if isValid {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Session Summary").font(.headline).foregroundColor(.white)
                                Divider().background(Color.gray.opacity(0.3))
                                if let wl = previewWL {
                                    SummaryRow(label: "Win/Loss",
                                               value: wl >= 0 ? "+$\(wl)" : "-$\(abs(wl))",
                                               color: wl >= 0 ? .green : .red)
                                }
                                SummaryRow(label: "Total Buy-In", value: "$\(session.totalBuyIn)", color: .white)
                                SummaryRow(label: "Hours Played", value: String(format: "%.2f", previewHours), color: .white)
                                if let e = previewTierEarned {
                                    SummaryRow(label: "Tier Points Earned",
                                               value: "\(e >= 0 ? "+" : "")\(e)",
                                               color: e >= 0 ? .green : .orange)
                                }
                                if let t = previewTPH {
                                    SummaryRow(label: "Tiers / Hour", value: String(format: "%.1f", t), color: .white)
                                }
                                if let t100 = previewT100 {
                                    SummaryRow(label: "Tiers per $100 Rated Bet-Hour",
                                               value: String(format: "%.2f", t100), color: .white)
                                }
                                if let wl = previewWL,
                                   let abet = Int(avgBetActual), abet > 0,
                                   let result = StrategyDatabase.expectedLossAndAboveEdge(gameName: session.game, winLoss: wl, avgBet: abet, hours: previewHours) {
                                    let above = result.aboveEdge >= 0
                                    let amount = Int(round(abs(result.aboveEdge)))
                                    SummaryRow(label: "Vs house edge",
                                               value: above ? "$\(amount) above" : "$\(amount) below",
                                               color: above ? .green : .orange)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)
                        }

                        VStack(spacing: 10) {
                            Button {
                                if let et = Int(endingTier), et < session.startingTierPoints {
                                    showLowAlert = true
                                } else { save() }
                            } label: {
                                Text("Save as Complete")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(isValid ? Color.green : Color.gray)
                                    .foregroundColor(isValid ? .black : .white)
                                    .cornerRadius(14).font(.headline)
                            }
                            .disabled(!isValid)

                            Button { dismiss() } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color(.systemGray6).opacity(0.2))
                                    .foregroundColor(.white).cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Complete Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                cashOut = session.cashOut.map { "\($0)" } ?? ""
                // Default ending tier to this session's starting/ending tier if available,
                // falling back to recent history for this casino.
                if endingTier.isEmpty {
                    if let et = session.endingTierPoints {
                        endingTier = "\(et)"
                    } else if session.startingTierPoints > 0 {
                        endingTier = "\(session.startingTierPoints)"
                    } else if let hist = store.defaultEndingTierPoints(for: session.casino) {
                        endingTier = "\(hist)"
                    }
                }
                // Pre-populate avg bets based on recent history for this game if missing.
                if avgBetActual.isEmpty || avgBetRated.isEmpty {
                    let defaults = store.defaultAvgBets(for: session.game)
                    if avgBetActual.isEmpty, let a = defaults.actual {
                        avgBetActual = "\(a)"
                    }
                    if avgBetRated.isEmpty, let r = defaults.rated {
                        avgBetRated = "\(r)"
                    }
                }
            }
            .alert("Tier Points Decreased", isPresented: $showLowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") { save() }
            } message: {
                Text("Ending tier (\(endingTier)) is lower than starting tier (\(session.startingTierPoints)). Save anyway?")
            }
        }
    }

    func save() {
        guard let co = Int(cashOut), let aba = Int(avgBetActual),
              let abr = Int(avgBetRated), let et = Int(endingTier) else { return }
        let netPositive = (co - session.totalBuyIn) > 0
        if netPositive {
            CelebrationPlayer.shared.celebrateWin()
            showCelebration = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                var updated = session
                updated.cashOut = co
                updated.avgBetActual = aba
                updated.avgBetRated = abr
                updated.endingTierPoints = et
                updated.status = .complete
                store.updateSession(updated)
                dismiss()
            }
        } else {
            var updated = session
            updated.cashOut = co
            updated.avgBetActual = aba
            updated.avgBetRated = abr
            updated.endingTierPoints = et
            updated.status = .complete
            store.updateSession(updated)
            dismiss()
        }
    }
}
