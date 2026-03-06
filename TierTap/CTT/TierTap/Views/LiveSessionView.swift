import SwiftUI

struct LiveSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var showBuyInSheet = false
    @State private var showCloseout = false

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                                    Text("Total: $\(s.totalBuyIn)")
                                        .font(.title3.bold()).foregroundColor(.white)
                                }
                                ForEach(s.buyInEvents) { ev in
                                    HStack {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.green).font(.caption)
                                        Text("$\(ev.amount)").foregroundColor(.white)
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

                            Button { showCloseout = true } label: {
                                Label("Stop & Close Out", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white).cornerRadius(14).font(.headline)
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
            .onChange(of: store.liveSession) { newVal in if newVal == nil { dismiss() } }
        }
    }
}
