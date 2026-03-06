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

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 6) {
                            Text(s.casino).font(.title2.bold()).foregroundColor(.white)
                            Text(s.game).foregroundColor(.gray)
                            HStack(spacing: 16) {
                                Label(Session.durationString(s.duration), systemImage: "clock")
                                Label("Buy-in: $\(s.totalBuyIn)", systemImage: "dollarsign.circle")
                            }
                            .font(.caption).foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Inputs
                        VStack(spacing: 14) {
                            InputRow(label: "Cash Out ($)", placeholder: "Amount leaving with", value: $cashOut)
                            InputRow(label: "Avg Bet Actual ($)", placeholder: "Your actual avg bet (no decimals)", value: $avgBetActual)
                            InputRow(label: "Avg Bet Rated ($)", placeholder: "Your rated avg bet (no decimals)", value: $avgBetRated)
                            InputRow(label: "Ending Tier Points", placeholder: "Check your loyalty app now", value: $endingTier)
                            if settingsStore.unitSize > 0,
                               (Int(avgBetActual) ?? 0) > settingsStore.unitSize || (Int(avgBetRated) ?? 0) > settingsStore.unitSize || s.totalBuyIn > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Bet or buy-in exceeds unit size ($\(settingsStore.unitSize)). Adjust in Settings to match your bankroll plan.")
                                        .font(.caption).foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }

                        // Live preview
                        if isValid {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Session Summary").font(.headline).foregroundColor(.white)
                                Divider().background(Color.gray.opacity(0.3))
                                if let wl = previewWL {
                                    SummaryRow(label: "Win/Loss",
                                               value: wl >= 0 ? "+$\(wl)" : "-$\(abs(wl))",
                                               color: wl >= 0 ? .green : .red)
                                }
                                SummaryRow(label: "Total Buy-In", value: "$\(s.totalBuyIn)", color: .white)
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
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)
                        }

                        VStack(spacing: 10) {
                            Button {
                                if let et = Int(endingTier), et < s.startingTierPoints {
                                    showLowAlert = true
                                } else { save() }
                            } label: {
                                Text("Save Session")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(isValid ? Color.green : Color.gray)
                                    .foregroundColor(isValid ? .black : .white)
                                    .cornerRadius(14).font(.headline)
                            }
                            .disabled(!isValid)

                            Button { dismiss() } label: {
                                Text("Cancel — Return to Session")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color(.systemGray6).opacity(0.2))
                                    .foregroundColor(.white).cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Tier Points Decreased", isPresented: $showLowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Save Anyway") { save() }
            } message: {
                Text("Ending tier (\(endingTier)) is lower than starting tier (\(s.startingTierPoints)). Save anyway?")
            }
        }
    }

    func save() {
        guard let co = Int(cashOut), let aba = Int(avgBetActual),
              let abr = Int(avgBetRated), let et = Int(endingTier) else { return }
        store.closeSession(cashOut: co, avgBetActual: aba, avgBetRated: abr, endingTier: et)
        dismiss()
    }
}
