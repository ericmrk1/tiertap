import SwiftUI

struct RiskOfRuinView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    private var result: RiskOfRuinResult {
        let currentBet: Int? = sessionStore.liveSession.map { max($0.totalBuyIn, $0.avgBetActual ?? 0) }
        return RiskOfRuinMath.compute(
            sessions: sessionStore.sessions,
            bankroll: settingsStore.bankroll,
            unitSize: settingsStore.unitSize,
            targetAveragePerSession: settingsStore.targetAveragePerSession,
            currentBetAmount: currentBet
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        chanceOfBustingCard
                        averageVsTargetCard
                        if result.betExceedsTarget { betWarningCard }
                        unitAndSessionsCard
                        mathNoteCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Risk of Ruin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
        }
    }

    private var chanceOfBustingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Chance of busting out", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundColor(.white)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(rorPercentString)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(rorColor)
                Text("risk of ruin")
                    .font(.subheadline).foregroundColor(.gray)
            }
            Text("Probability of losing your entire bankroll based on your session history and current bankroll/unit settings.")
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var rorPercentString: String {
        if result.sessionCount == 0 {
            return "—"
        }
        let pct = result.riskOfRuin * 100
        if pct >= 99.5 { return "~100%" }
        if pct <= 0.5 { return "<1%" }
        return String(format: "%.1f%%", pct)
    }

    private var rorColor: Color {
        if result.sessionCount == 0 { return .gray }
        if result.riskOfRuin >= 0.25 { return .red }
        if result.riskOfRuin >= 0.10 { return .orange }
        return .green
    }

    private var averageVsTargetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Average vs target", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline).foregroundColor(.white)
            if result.sessionCount == 0 {
                Text("Add closed sessions to see your average win/loss per session and compare to your target.")
                    .font(.subheadline).foregroundColor(.gray)
            } else {
                HStack {
                    Text("Actual average")
                        .font(.subheadline).foregroundColor(.gray)
                    Spacer()
                    Text(formatDollars(result.actualAveragePerSession))
                        .font(.subheadline.bold())
                        .foregroundColor((result.actualAveragePerSession ?? 0) >= 0 ? .green : .red)
                }
                if let target = result.targetAveragePerSession {
                    HStack {
                        Text("Target average")
                            .font(.subheadline).foregroundColor(.gray)
                        Spacer()
                        Text(formatDollars(target))
                            .font(.subheadline.bold()).foregroundColor(.white)
                    }
                    if let actual = result.actualAveragePerSession {
                        let gap = actual - target
                        HStack {
                            Text("Gap")
                                .font(.subheadline).foregroundColor(.gray)
                            Spacer()
                            Text((gap >= 0 ? "+" : "") + formatDollars(gap))
                                .font(.subheadline.bold())
                                .foregroundColor(gap >= 0 ? .green : .orange)
                        }
                    }
                } else {
                    Text("Set a target in Settings to compare.")
                        .font(.caption).foregroundColor(.gray)
                }
                if let wr = result.winRate {
                    HStack {
                        Text("Win rate (sessions)")
                            .font(.subheadline).foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.0f%%", wr * 100))
                            .font(.subheadline.bold()).foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var betWarningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title2).foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bet exceeds target unit")
                    .font(.headline).foregroundColor(.orange)
                Text("Your current buy-in or average bet is above your set unit size ($\(result.recommendedUnitSize)). Consider lowering bet size to stay within bankroll management target.")
                    .font(.caption).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.5), lineWidth: 1))
    }

    private var unitAndSessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Bankroll", value: "$\(settingsStore.bankroll)")
            DetailRow(label: "Unit size", value: "$\(settingsStore.unitSize)")
            DetailRow(label: "Sessions used", value: "\(result.sessionCount)")
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var mathNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it's calculated")
                .font(.caption.bold()).foregroundColor(.gray)
            Text("Risk of ruin uses the session-based formula: RoR = (q/p)^(bankroll/unit), where p = proportion of winning sessions and q = proportion of losing sessions from your history. With negative or break-even edge, ruin is certain over time. Set bankroll and unit size in Settings.")
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(12)
    }

    private func formatDollars(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        let sign = v >= 0 ? "+" : ""
        return sign + "$\(Int(round(v)))"
    }
}
