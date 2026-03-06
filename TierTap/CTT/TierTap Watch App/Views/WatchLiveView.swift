import SwiftUI

struct WatchLiveView: View {
    @EnvironmentObject var store: SessionStore
    @State private var elapsed: TimeInterval = 0
    @State private var showAddBuyIn = false
    @State private var showCashOut = false

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let quickAmounts = [100, 200, 300, 500]

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE").font(.caption2.bold()).foregroundColor(.red)
                }

                Text(s.casino)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(s.game)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(Session.durationString(elapsed))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.green)

                Text("Buy-in: $\(s.totalBuyIn)")
                    .font(.caption)

                if showAddBuyIn {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add buy-in").font(.caption2)
                        HStack(spacing: 6) {
                            ForEach(quickAmounts, id: \.self) { amt in
                                Button("$\(amt)") {
                                    store.addBuyIn(amt)
                                    showAddBuyIn = false
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                    }
                } else {
                    Button {
                        showAddBuyIn = true
                    } label: {
                        Label("Add buy-in", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }

                Button {
                    showCashOut = true
                } label: {
                    Label("Cash out", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
        }
        .navigationTitle("Session")
        .onReceive(ticker) { _ in
            elapsed = Date().timeIntervalSince(s.startTime)
        }
        .onAppear {
            elapsed = Date().timeIntervalSince(s.startTime)
        }
        .sheet(isPresented: $showCashOut) {
            WatchCashOutView()
                .environmentObject(store)
        }
    }
}
