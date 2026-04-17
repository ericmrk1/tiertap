import SwiftUI
import UIKit

struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var showCompleteSession = false
    @State private var showEditSession = false
    @State private var privateNotes: String = ""
    @State private var tierPointsVerification: SessionTierPointsVerification = .verified

    /// Latest session from the store so the detail updates after edits.
    private var displaySession: Session {
        store.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if displaySession.requiresMoreInfo {
                            Button {
                                showCompleteSession = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                    L10nText("Complete session — add avg bet & ending tier")
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
                            Text(displaySession.casino).font(.title.bold()).foregroundColor(.white)
                            Text(displaySession.game).font(.subheadline).foregroundColor(.gray)
                            Text(displaySession.startTime, style: .date).font(.caption).foregroundColor(.gray)
                            if let mood = displaySession.sessionMood {
                                Text(mood.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6).opacity(0.15)).cornerRadius(16)

                        if hasSessionPhotosContent {
                            DetailSection(title: "Session Photos", icon: "photo.on.rectangle.angled") {
                                VStack(alignment: .leading, spacing: 16) {
                                    if let fileName = displaySession.chipEstimatorImageFilename,
                                       let url = ChipEstimatorPhotoStorage.url(for: fileName),
                                       let uiImage = UIImage(contentsOfFile: url.path) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            L10nText("Session")
                                                .font(.caption.bold())
                                                .foregroundColor(.gray)
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        }
                                    }
                                    ForEach(displaySession.compEvents.filter { compHasReceiptPhoto($0.id) }) { ev in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Comp receipt · \(settingsStore.currencySymbol)\(ev.amount) · \(ev.timestamp.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption.bold())
                                                .foregroundColor(.gray)
                                            if let url = CompPhotoStorage.url(for: ev.id),
                                               let ui = UIImage(contentsOfFile: url.path) {
                                                Image(uiImage: ui)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(12)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Metrics highlights
                        HStack(spacing: 12) {
                            if let e = displaySession.tierPointsEarned {
                                MetricCard(title: "Pts Earned",
                                           value: "\(e >= 0 ? "+" : "")\(e)",
                                           color: e >= 0 ? .green : .orange)
                            }
                            if let wl = displaySession.winLoss {
                                MetricCard(title: "Win/Loss",
                                           value: wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))",
                                           color: wl >= 0 ? .green : .red)
                            }
                            if let ev = displaySession.expectedValue {
                                MetricCard(title: "EV",
                                           value: ev >= 0 ? "+\(settingsStore.currencySymbol)\(ev)" : "-\(settingsStore.currencySymbol)\(abs(ev))",
                                           color: ev >= 0 ? .green : .red)
                            }
                            if let rate = displaySession.winRatePerHour {
                                MetricCard(title: "Win Rate",
                                           value: String(format: "%@%.0f/hr",
                                                         rate >= 0 ? "+\(settingsStore.currencySymbol)" : "-\(settingsStore.currencySymbol)",
                                                         fabs(rate)),
                                           color: rate >= 0 ? .green : .red)
                            }
                        }

                        DetailSection(title: "Session Time", icon: "clock") {
                            DetailRow(label: "Started", value: displaySession.startTime.formatted(date: .omitted, time: .shortened))
                            if let end = displaySession.endTime {
                                DetailRow(label: "Ended", value: end.formatted(date: .omitted, time: .shortened))
                            }
                            DetailRow(label: "Duration", value: Session.durationString(displaySession.duration))
                            DetailRow(label: "Hours", value: String(format: "%.2f hrs", displaySession.hoursPlayed))
                        }

                        DetailSection(title: "Buy-Ins", icon: "dollarsign.circle") {
                            ForEach(displaySession.buyInEvents) { ev in
                                DetailRow(label: ev.timestamp.formatted(date: .omitted, time: .shortened),
                                          value: "\(settingsStore.currencySymbol)\(ev.amount)")
                            }
                            DetailRow(label: "Total Buy-In", value: "\(settingsStore.currencySymbol)\(displaySession.totalBuyIn)", bold: true)
                            if !displaySession.compEvents.isEmpty {
                                ForEach(displaySession.compEvents) { ev in
                                    DetailRow(
                                        label: ev.timestamp.formatted(date: .omitted, time: .shortened),
                                        value: "\(settingsStore.currencySymbol)\(ev.amount)"
                                    )
                                }
                                DetailRow(label: "Total Comps", value: "\(settingsStore.currencySymbol)\(displaySession.totalComp)", bold: true)
                            }
                            if let co = displaySession.cashOut {
                                DetailRow(label: "Cash Out", value: "\(settingsStore.currencySymbol)\(co)", bold: true)
                            }
                            if let wl = displaySession.winLoss {
                                DetailRow(label: "Win/Loss",
                                          value: wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))",
                                          valueColor: wl >= 0 ? .green : .red, bold: true)
                            }
                            if let ev = displaySession.expectedValue {
                                DetailRow(label: "EV (win/loss + comps)",
                                          value: ev >= 0 ? "+\(settingsStore.currencySymbol)\(ev)" : "-\(settingsStore.currencySymbol)\(abs(ev))",
                                          valueColor: ev >= 0 ? .green : .red, bold: true)
                            }
                        }

                        if let aba = displaySession.avgBetActual, let abr = displaySession.avgBetRated {
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
                            VStack(alignment: .leading, spacing: 8) {
                                L10nText("Verification")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Picker("", selection: $tierPointsVerification) {
                                    Text("Verified").tag(SessionTierPointsVerification.verified)
                                    Text("Unverified").tag(SessionTierPointsVerification.unverified)
                                }
                                .pickerStyle(.segmented)
                                .tint(.green)
                            }
                            DetailRow(label: "Starting", value: "\(displaySession.startingTierPoints)")
                            if let et = displaySession.endingTierPoints {
                                DetailRow(label: "Ending", value: "\(et)")
                            }
                            if let e = displaySession.tierPointsEarned {
                                DetailRow(label: "Earned",
                                          value: "\(e >= 0 ? "+" : "")\(e)",
                                          valueColor: e >= 0 ? .green : .orange, bold: true)
                            }
                        }

                        DetailSection(title: "Metrics", icon: "chart.line.uptrend.xyaxis") {
                            if let t = displaySession.tiersPerHour {
                                DetailRow(label: "Tiers / Hour", value: String(format: "%.2f", t))
                            }
                            if let t100 = displaySession.tiersPerHundredRatedBetHour {
                                DetailRow(label: "Tiers per 100 \(settingsStore.currencySymbol) Rated Bet-Hour",
                                          value: String(format: "%.3f", t100))
                            }
                            if let wl = displaySession.winLoss,
                               let abet = displaySession.avgBetActual ?? displaySession.avgBetRated, abet > 0,
                               displaySession.hoursPlayed > 0,
                               let result = StrategyDatabase.expectedLossAndAboveEdge(gameName: displaySession.game, winLoss: wl, avgBet: abet, hours: displaySession.hoursPlayed) {
                                let above = result.aboveEdge >= 0
                                let amount = Int(round(abs(result.aboveEdge)))
                                DetailRow(label: "Vs house edge",
                                          value: above ? "\(settingsStore.currencySymbol)\(amount) above" : "\(settingsStore.currencySymbol)\(amount) below",
                                          valueColor: above ? .green : .orange)
                            }
                        }

                        if displaySession.gameCategory == .poker ||
                            displaySession.pokerSmallBlind != nil ||
                            displaySession.pokerBigBlind != nil ||
                            displaySession.pokerAnte != nil ||
                            displaySession.pokerLevelMinutes != nil ||
                            displaySession.pokerStartingStack != nil {
                            DetailSection(title: "Poker Structure", icon: "suit.club.fill") {
                                if let sb = displaySession.pokerSmallBlind, let bb = displaySession.pokerBigBlind {
                                    DetailRow(
                                        label: "Blinds",
                                        value: "\(settingsStore.currencySymbol)\(sb)/\(settingsStore.currencySymbol)\(bb)\(displaySession.pokerAnte.map { " (ante \(settingsStore.currencySymbol)\($0))" } ?? "")"
                                    )
                                } else if let sb = displaySession.pokerSmallBlind {
                                    DetailRow(
                                        label: "Small blind",
                                        value: "\(settingsStore.currencySymbol)\(sb)"
                                    )
                                } else if let bb = displaySession.pokerBigBlind {
                                    DetailRow(
                                        label: "Big blind",
                                        value: "\(settingsStore.currencySymbol)\(bb)"
                                    )
                                }

                                if let minutes = displaySession.pokerLevelMinutes {
                                    DetailRow(
                                        label: "Level clock",
                                        value: "\(minutes) min"
                                    )
                                }
                                if let stack = displaySession.pokerStartingStack {
                                    DetailRow(
                                        label: "Starting stack",
                                        value: "\(stack) chips"
                                    )
                                }
                            }
                        }

                        if displaySession.hasSlotMetadata {
                            DetailSection(title: "Slot details", icon: "square.grid.3x3.fill") {
                                if let line = displaySession.slotFormatDisplayLabel {
                                    DetailRow(label: "Format", value: line)
                                }
                                if let line = displaySession.slotFeatureDisplayLabel {
                                    DetailRow(label: "Major feature", value: line)
                                }
                                if let n = displaySession.slotNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                                    DetailRow(label: "Notes", value: n)
                                }
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
            .onAppear {
                privateNotes = displaySession.privateNotes ?? ""
                tierPointsVerification = displaySession.effectiveTierPointsVerification
            }
            .onChange(of: showEditSession) { isEditing in
                if !isEditing {
                    privateNotes = displaySession.privateNotes ?? ""
                    tierPointsVerification = displaySession.effectiveTierPointsVerification
                }
            }
            .onChange(of: tierPointsVerification) { newValue in
                guard let idx = store.sessions.firstIndex(where: { $0.id == displaySession.id }) else { return }
                var s = store.sessions[idx]
                if s.tierPointsVerification == nil, newValue == .verified { return }
                guard s.tierPointsVerification != newValue else { return }
                s.tierPointsVerification = newValue
                store.updateSession(s)
            }
            .onDisappear {
                let trimmed = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let idx = store.sessions.firstIndex(where: { $0.id == displaySession.id }) else { return }
                var s = store.sessions[idx]
                let newNotes = trimmed.isEmpty ? nil : trimmed
                if s.privateNotes != newNotes {
                    s.privateNotes = newNotes
                    store.updateSession(s)
                }
            }
            .localizedNavigationTitle("Session Detail")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditSession = true
                    } label: {
                        L10nText("Edit")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit session information")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.green)
                }
            }
            .adaptiveSheet(isPresented: $showCompleteSession) {
                CompleteSessionView(session: displaySession)
                    .environmentObject(store)
                    .environmentObject(rewardWalletStore)
                    .environmentObject(settingsStore)
            }
            .adaptiveSheet(isPresented: $showEditSession) {
                EditSessionView(session: displaySession)
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
            }
        }
    }

    private func compHasReceiptPhoto(_ id: UUID) -> Bool {
        guard let url = CompPhotoStorage.url(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var hasSessionPhotosContent: Bool {
        if let fileName = displaySession.chipEstimatorImageFilename,
           let url = ChipEstimatorPhotoStorage.url(for: fileName),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return displaySession.compEvents.contains { compHasReceiptPhoto($0.id) }
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
