import SwiftUI

struct LiveSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var showBuyInSheet = false
    @State private var showCloseout = false
    @State private var showStrategyOdds = false
    @State private var showPrivateNotes = false
    @State private var showMissingInfoAlert = false

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Required fields that must be set before closing out. Returns list of missing item names.
    private var missingInfoFields: [String] {
        var missing: [String] = []
        if s.game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Game") }
        if s.casino.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Casino / Location") }
        if s.buyInEvents.isEmpty { missing.append("At least one buy-in") }
        return missing
    }

    private var hasMissingInfo: Bool { !missingInfoFields.isEmpty }

    /// Quick-add buy-in denominations for the live buy-in sheet.
    private var quickBuyIns: [Int] {
        [50, 100, 200, 500, 1_000, 5_000, 10_000, 20_000, 50_000, 100_000]
    }

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Timer Hero
                    VStack(spacing: 6) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                Text("LIVE").font(.caption.bold()).foregroundColor(.red)
                            }
                            Spacer()
                            Text("Started \(s.startTime, style: .time)")
                                .font(.caption).foregroundColor(.gray)
                        }
                        Text(s.casino).font(.title2.bold()).foregroundColor(.white)
                        Text(s.game).font(.subheadline).foregroundColor(.gray)
                        Text(Session.durationString(elapsed))
                            .font(.system(size: 60, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.vertical, 4)

                        HStack(spacing: 10) {
                            Button { showPrivateNotes = true } label: {
                                Image(systemName: "note.text")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.green)
                                    .frame(width: 44, height: 36)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .cornerRadius(10)
                            }
                            .accessibilityLabel("Private notes")
                            Button { showStrategyOdds = true } label: {
                                Text("Strategy/Odds")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.12))

                    ScrollView {
                        VStack(spacing: 16) {
                            // Buy-In Panel
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Buy-Ins").font(.headline).foregroundColor(.white)
                                    Spacer()
                                    Text("Total: \(settingsStore.currencySymbol)\(s.totalBuyIn)")
                                        .font(.title3.bold()).foregroundColor(.white)
                                }
                                ForEach(s.buyInEvents) { ev in
                                    HStack {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.green).font(.caption)
                                        Text("\(settingsStore.currencySymbol)\(ev.amount)").foregroundColor(.white)
                                        Spacer()
                                        Text(ev.timestamp, style: .time)
                                            .font(.caption).foregroundColor(.gray)
                                    }
                                }
                                Button {
                                    showBuyInSheet = true
                                } label: {
                                    Label("Add Buy-In", systemImage: "plus.circle")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal)
                                        .background(Color(.systemGray6).opacity(0.25))
                                        .foregroundColor(.green)
                                        .cornerRadius(14)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)

                            HStack(spacing: 12) {
                                StatMini(title: "Hours", value: String(format: "%.1f", s.hoursPlayed))
                                StatMini(title: "Start Pts", value: "\(s.startingTierPoints)")
                            }

                            Button {
                                if hasMissingInfo {
                                    showMissingInfoAlert = true
                                } else {
                                    showCloseout = true
                                }
                            } label: {
                                Label("Stop & Close Out", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white).cornerRadius(14).font(.headline)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Private notes (not shared)")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                TextEditor(text: Binding(
                                    get: { store.liveSession?.privateNotes ?? "" },
                                    set: { store.updateLiveSessionNotes($0) }
                                ))
                                .frame(minHeight: 72)
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
            }
            .navigationTitle("Live Session")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.foregroundColor(.green)
                }
            }
            .onReceive(ticker) { _ in elapsed = Date().timeIntervalSince(s.startTime) }
            .onAppear { elapsed = Date().timeIntervalSince(s.startTime) }
            .sheet(isPresented: $showBuyInSheet) {
                BuyInQuickAddSheet(quickBuyIns: quickBuyIns) { amount in
                    store.addBuyIn(amount)
                }
                .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showCloseout) { CloseoutView().environmentObject(store).environmentObject(settingsStore) }
            .sheet(isPresented: $showStrategyOdds) {
                StrategyOddsSheet(gameName: s.game)
                    .environmentObject(settingsStore)
            }
            .sheet(isPresented: $showPrivateNotes) {
                PrivateNotesSheet(
                    notes: Binding(
                        get: { store.liveSession?.privateNotes ?? "" },
                        set: { store.updateLiveSessionNotes($0) }
                    ),
                    onDismiss: { showPrivateNotes = false }
                )
                .environmentObject(settingsStore)
            }
            .onChange(of: store.liveSession) { newVal in if newVal == nil { dismiss() } }
            .alert("Missing Information", isPresented: $showMissingInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please complete the following before closing out: \(missingInfoFields.joined(separator: ", ")). You can add buy-ins here, but game and location must be set when you check in.")
            }
        }
    }
}

/// Sheet for editing private session notes (local only, not shared).
struct PrivateNotesSheet: View {
    @Binding var notes: String
    let onDismiss: () -> Void
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Private notes (stored locally only, not shared)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .scrollContentBackground(.hidden)
                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Private Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }
}
