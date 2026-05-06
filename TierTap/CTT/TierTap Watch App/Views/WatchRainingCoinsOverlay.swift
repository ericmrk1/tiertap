import SwiftUI

#if os(watchOS)
/// Full-screen falling chip/coin rain for short celebrations. watchOS has no `keyboardType(.numberPad)`; this is purely visual.
struct WatchRainingCoinsOverlay: View {
    /// Increment to play a new rain burst.
    var playToken: Int
    /// When false, the overlay stays inert (reduce motion or watch animations off).
    var enabled: Bool

    @State private var coins: [FallingCoin] = []
    @State private var rainEpoch: Date?
    @State private var clearWorkItem: DispatchWorkItem?

    private let coinCount = 34

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if coins.isEmpty {
                Color.clear
            } else if let epoch = rainEpoch {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSince(epoch)
                    ZStack {
                        ForEach(coins) { coin in
                            let local = t - coin.spawnOffset
                            if local >= 0 {
                                let progress = min(1.0, local / coin.fallDuration)
                                let eased = 1 - pow(1 - progress, 1.35)
                                let x = coin.xNormalized * w
                                    + sin(eased * .pi * 2.2 + coin.phase) * 14 * CGFloat(coin.wobble)
                                let y = -h * 0.08 + CGFloat(eased) * h * 1.18
                                let spin = coin.spin0 + coin.spinSpeed * local * 360 / (2 * .pi)
                                Image("TierTap_C_PokerChip")
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(width: coin.size, height: coin.size)
                                    .clipShape(Circle())
                                    .rotationEffect(.degrees(spin))
                                    .position(x: x, y: y)
                                    .opacity(progress < 1 ? 1 : 0)
                            }
                        }
                    }
                    .frame(width: w, height: h)
                }
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: playToken) { _, newVal in
            guard enabled, newVal > 0 else {
                coins = []
                rainEpoch = nil
                clearWorkItem?.cancel()
                return
            }
            clearWorkItem?.cancel()
            coins = (0..<coinCount).map { FallingCoin(index: $0, seed: UInt64(newVal &* 1_000_003 &+ 17)) }
            rainEpoch = Date()
            let maxEnd = coins.map { $0.spawnOffset + $0.fallDuration }.max() ?? 2.4
            let work = DispatchWorkItem {
                rainEpoch = nil
                coins = []
            }
            clearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + maxEnd + 0.15, execute: work)
        }
    }
}

private struct FallingCoin: Identifiable {
    let id: Int
    let spawnOffset: TimeInterval
    let fallDuration: TimeInterval
    let xNormalized: CGFloat
    let wobble: Double
    let phase: Double
    let size: CGFloat
    let spin0: Double
    let spinSpeed: Double

    init(index: Int, seed: UInt64) {
        id = index
        var s = seed &+ UInt64(index &* 97)
        func next() -> Double {
            s = s &* 6_364_136_223_846_793_005 &+ 1
            let z = (s >> 33) ^ s
            return Double(z % 1_000_000) / 1_000_000.0
        }
        spawnOffset = next() * 1.35
        fallDuration = 0.95 + next() * 1.15
        xNormalized = CGFloat(0.06 + next() * 0.88)
        wobble = 0.35 + next() * 1.0
        phase = next() * .pi * 2
        size = CGFloat(14 + next() * 16)
        spin0 = next() * 360
        spinSpeed = -1.8 + next() * 3.6
    }
}
#endif
