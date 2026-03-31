import SwiftUI

/// Full-screen confetti burst; increment `burstID` (from a non-zero value) to replay.
struct ConfettiBurstView: View {
    var burstID: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if burstID > 0 {
                    ForEach(0..<56, id: \.self) { i in
                        ConfettiPiece(
                            index: i,
                            burstID: burstID,
                            width: geo.size.width,
                            height: geo.size.height
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let burstID: Int
    let width: CGFloat
    let height: CGFloat

    @State private var fallen = false

    private var colors: [Color] {
        [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink]
    }

    var body: some View {
        let c = colors[index % colors.count]
        let xNorm = CGFloat((index * 47 + burstID * 19) % 100) / 100
        let x = max(8, min(width - 8, xNorm * width))
        let rotEnd = Double((index * 73 + burstID) % 720) - 360
        let dur = 1.85 + Double(index % 12) * 0.04

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(c)
            .frame(width: 7, height: 10 + CGFloat(index % 5))
            .rotationEffect(.degrees(fallen ? rotEnd : Double(index % 40)))
            .position(x: x, y: fallen ? height + 44 : -28)
            .animation(.easeIn(duration: dur).delay(Double(index) * 0.018), value: fallen)
            .onAppear { startFall() }
            .onChange(of: burstID) { _, _ in startFall() }
    }

    private func startFall() {
        fallen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            fallen = true
        }
    }
}
