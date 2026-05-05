import SwiftUI

/// Short confetti burst when a live stack update shows a session profit (stack above total buy-in).
struct StackWinConfettiBurst: View {
    /// Increment to replay the burst.
    var burstID: Int
    /// When false, the view is inert (e.g. reduce motion or watch animations off).
    var enabled: Bool

    @State private var pieces: [ConfettiPiece] = []
    @State private var burstStart: Date?

    private var particleCount: Int {
        #if os(watchOS)
        10
        #else
        26
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.14)
            if pieces.isEmpty {
                Color.clear
                    .allowsHitTesting(false)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    let elapsed = burstStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                    ZStack {
                        ForEach(pieces) { p in
                            let localT = max(0, elapsed - p.delay)
                            let progress = min(1, localT / p.duration)
                            let eased = 1 - pow(1 - progress, 2)
                            let x = center.x + CGFloat(p.vx) * CGFloat(eased) * geo.size.width * 0.42
                            let y = center.y
                                + CGFloat(p.vy0) * CGFloat(eased) * geo.size.height * 0.55
                                + 0.5 * CGFloat(localT * localT) * 180
                            Capsule()
                                .fill(p.color)
                                .frame(width: p.width, height: p.height)
                                .rotationEffect(.degrees(p.spinStart + (p.spinEnd - p.spinStart) * eased))
                                .position(x: x, y: y)
                                .opacity(1 - eased * 0.45)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: burstID) { newVal in
            guard enabled, newVal > 0 else { return }
            pieces = (0..<particleCount).map { i in
                ConfettiPiece(index: i, seed: UInt64(bitPattern: Int64(newVal &* 1_046_529 &+ i)))
            }
            burstStart = Date()
            let maxEnd = pieces.map { $0.delay + $0.duration }.max() ?? 1.05
            DispatchQueue.main.asyncAfter(deadline: .now() + maxEnd + 0.12) {
                burstStart = nil
                pieces = []
            }
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let delay: TimeInterval
    let duration: TimeInterval
    let vx: Double
    let vy0: Double
    let spinStart: Double
    let spinEnd: Double
    let width: CGFloat
    let height: CGFloat
    let color: Color

    init(index: Int, seed: UInt64) {
        var g = seed &+ UInt64(index &* 97)
        func next() -> UInt64 {
            g = g &* 6364136223846793005 &+ 1
            return g
        }
        func unit() -> Double { Double(next() % 10_000) / 10_000 }
        delay = unit() * 0.07
        duration = 0.72 + unit() * 0.38
        vx = (unit() - 0.5) * 2.0
        vy0 = 0.15 + unit() * 0.55
        spinStart = (unit() - 0.5) * 40
        spinEnd = spinStart + (unit() - 0.5) * 520
        let base = 2.8 + CGFloat(unit()) * 3.8
        if unit() > 0.5 {
            width = base * 1.15
            height = base * 0.55
        } else {
            width = base * 0.55
            height = base * 1.15
        }
        let hues: [Color] = [.yellow, .green, .orange, .cyan, .pink, .mint]
        color = hues[Int(next() % UInt64(hues.count))]
    }
}
