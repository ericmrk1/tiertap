import SwiftUI

/// Remote control for the live session running on iPhone: rebuy and stop.
struct WatchLiveView: View {
    @EnvironmentObject var store: SessionStore
    @State private var elapsed: TimeInterval = 0

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let rebuyAmounts = [100, 200, 300, 500]

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Image("TierTap_C_PokerChip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE").font(.caption2.bold()).foregroundColor(.red)
                }

                Text(s.casino)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(s.game)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Start tier \(s.startingTierPoints.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let prog = s.rewardsProgramName?.trimmingCharacters(in: .whitespacesAndNewlines), !prog.isEmpty {
                    Text(prog)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Text(Session.durationString(elapsed))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.green)

                Text("Total buy-in $\(s.totalBuyIn.formatted(.number.grouping(.automatic)))")
                    .font(.caption2)

                Text("Rebuy").font(.caption2)
                HStack(spacing: 6) {
                    ForEach(rebuyAmounts, id: \.self) { amt in
                        Button("$\(amt)") {
                            store.addBuyIn(amt)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }

                Button {
                    store.closeSessionCashOutOnly(cashOut: s.totalBuyIn)
                } label: {
                    Label("Stop session", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
        }
        .navigationTitle("Remote")
        .onReceive(ticker) { _ in
            elapsed = Date().timeIntervalSince(s.startTime)
        }
        .onAppear {
            elapsed = Date().timeIntervalSince(s.startTime)
        }
    }
}
