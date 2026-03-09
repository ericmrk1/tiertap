import SwiftUI

struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var showCompleteSession = false
    @State private var privateNotes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if session.requiresMoreInfo {
                            Button {
                                showCompleteSession = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                    Text("Complete session — add avg bet & ending tier")
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity).padding()
                                .background(Color.orange.opacity(0.3))
                                .foregroundColor(.orange)
                                .cornerRadius(14)
                            }
                            .padding(.horizontal)
                        }

                        // Header
                        VStack(spacing: 6) {
                            Text(session.casino).font(.title.bold()).foregroundColor(.white)
                            Text(session.game).font(.subheadline).foregroundColor(.gray)
                            Text(session.startTime, style: .date).font(.caption).foregroundColor(.gray)
                            if let mood = session.sessionMood {
                                Text(mood.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray6).opacity(0.15)).cornerRadius(16)

                        // Metrics highlights
                        HStack(spacing: 12) {
                            if let e = session.tierPointsEarned {
                                MetricCard(title: "Pts Earned",
                                           value: "\(e >= 0 ? "+" : "")\(e)",
                                           color: e >= 0 ? .green : .orange)
                            }
                            if let wl = session.winLoss {
                                MetricCard(title: "Win/Loss",
                                           value: wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))",
                                           color: wl >= 0 ? .green : .red)
                            }
                            if let t = session.tiersPerHour {
                                MetricCard(title: "Pts/Hour", value: String(format: "%.1f", t), color: .white)
                            }
                        }

                        DetailSection(title: "Session Time", icon: "clock") {
                            DetailRow(label: "Started", value: session.startTime.formatted(date: .omitted, time: .shortened))
                            if let end = session.endTime {
                                DetailRow(label: "Ended", value: end.formatted(date: .omitted, time: .shortened))
                            }
                            DetailRow(label: "Duration", value: Session.durationString(session.duration))
                            DetailRow(label: "Hours", value: String(format: "%.2f hrs", session.hoursPlayed))
                        }

                        DetailSection(title: "Buy-Ins", icon: "dollarsign.circle") {
                            ForEach(session.buyInEvents) { ev in
                                DetailRow(label: ev.timestamp.formatted(date: .omitted, time: .shortened),
                                          value: "\(settingsStore.currencySymbol)\(ev.amount)")
                            }
                            DetailRow(label: "Total Buy-In", value: "\(settingsStore.currencySymbol)\(session.totalBuyIn)", bold: true)
                            if let co = session.cashOut {
                                DetailRow(label: "Cash Out", value: "\(settingsStore.currencySymbol)\(co)", bold: true)
                            }
                            if let wl = session.winLoss {
                                DetailRow(label: "Win/Loss",
                                          value: wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))",
                                          valueColor: wl >= 0 ? .green : .red, bold: true)
                            }
                        }

                        if let aba = session.avgBetActual, let abr = session.avgBetRated {
                            DetailSection(title: "Betting", icon: "chart.bar") {
                                DetailRow(label: "Avg Bet Actual", value: "\(settingsStore.currencySymbol)\(aba)")
                                DetailRow(label: "Avg Bet Rated", value: "\(settingsStore.currencySymbol)\(abr)")
                                if abr < 100 {
                                    Text("Tiers per 100 \(settingsStore.currencySymbol) metric requires rated avg bet ≥ 100")
                                        .font(.caption).foregroundColor(.gray).padding(.top, 4)
                                }
                            }
                        }

                        DetailSection(title: "Tier Points", icon: "star.circle") {
                            DetailRow(label: "Starting", value: "\(session.startingTierPoints)")
                            if let et = session.endingTierPoints {
                                DetailRow(label: "Ending", value: "\(et)")
                            }
                            if let e = session.tierPointsEarned {
                                DetailRow(label: "Earned",
                                          value: "\(e >= 0 ? "+" : "")\(e)",
                                          valueColor: e >= 0 ? .green : .orange, bold: true)
                            }
                        }

                        DetailSection(title: "Metrics", icon: "chart.line.uptrend.xyaxis") {
                            if let t = session.tiersPerHour {
                                DetailRow(label: "Tiers / Hour", value: String(format: "%.2f", t))
                            }
                            if let t100 = session.tiersPerHundredRatedBetHour {
                                DetailRow(label: "Tiers per 100 \(settingsStore.currencySymbol) Rated Bet-Hour",
                                          value: String(format: "%.3f", t100))
                            }
                            if let wl = session.winLoss,
                               let abet = session.avgBetActual ?? session.avgBetRated, abet > 0,
                               session.hoursPlayed > 0,
                               let result = StrategyDatabase.expectedLossAndAboveEdge(gameName: session.game, winLoss: wl, avgBet: abet, hours: session.hoursPlayed) {
                                let above = result.aboveEdge >= 0
                                let amount = Int(round(abs(result.aboveEdge)))
                                DetailRow(label: "Vs house edge",
                                          value: above ? "\(settingsStore.currencySymbol)\(amount) above" : "\(settingsStore.currencySymbol)\(amount) below",
                                          valueColor: above ? .green : .orange)
                            }
                        }

                        DetailSection(title: "Private notes (not shared)", icon: "note.text") {
                            TextEditor(text: $privateNotes)
                                .frame(minHeight: 88)
                                .padding(8)
                                .background(Color(.systemGray6).opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding()
                }
            }
            .onAppear { privateNotes = session.privateNotes ?? "" }
            .onDisappear {
                let trimmed = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let idx = store.sessions.firstIndex(where: { $0.id == session.id }) else { return }
                var s = store.sessions[idx]
                let newNotes = trimmed.isEmpty ? nil : trimmed
                if s.privateNotes != newNotes {
                    s.privateNotes = newNotes
                    store.updateSession(s)
                }
            }
            .navigationTitle("Session Detail")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showCompleteSession) {
                CompleteSessionView(session: session)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
            }
        }
    }
}

struct MetricCard: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundColor(.gray)
            Text(value).font(.headline.bold()).foregroundColor(color)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(12)
        .background(Color(.systemGray6).opacity(0.2)).cornerRadius(12)
    }
}
