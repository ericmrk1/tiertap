import SwiftUI

enum SessionClosingMetricsPeriod: String, CaseIterable, Identifiable {
    case today
    case month
    case allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .month: return "Month"
        case .allTime: return "All Time"
        }
    }

    func includes(_ session: Session, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        switch self {
        case .today:
            return calendar.isDate(session.startTime, inSameDayAs: now)
        case .month:
            return calendar.isDate(session.startTime, equalTo: now, toGranularity: .month)
                && calendar.isDate(session.startTime, equalTo: now, toGranularity: .year)
        case .allTime:
            return true
        }
    }
}

struct SessionClosingMetricsSnapshot: Equatable {
    var verifiedFraction: Double
    var publishedFraction: Double
    var verifiedCount: Int
    var publishedCount: Int
    var totalCount: Int

    static let empty = SessionClosingMetricsSnapshot(
        verifiedFraction: 0,
        publishedFraction: 0,
        verifiedCount: 0,
        publishedCount: 0,
        totalCount: 0
    )

    static func compute(from sessions: [Session], period: SessionClosingMetricsPeriod) -> SessionClosingMetricsSnapshot {
        let filtered = sessions.filter { period.includes($0) }
        let total = filtered.count
        guard total > 0 else { return .empty }

        let verified = filtered.filter { $0.effectiveTierPointsVerification == .verified }.count
        let published = filtered.filter { $0.isPublishedToCommunity }.count
        let denom = Double(total)

        return SessionClosingMetricsSnapshot(
            verifiedFraction: Double(verified) / denom,
            publishedFraction: Double(published) / denom,
            verifiedCount: verified,
            publishedCount: published,
            totalCount: total
        )
    }
}

struct SessionClosingMetricsRingsView: View {
    let sessions: [Session]
    @Binding var period: SessionClosingMetricsPeriod
    /// When true, rings animate from 0% up to their current levels.
    var isRevealed: Bool = true
    /// Smaller rings/legend for the home Sessions carousel.
    var compact: Bool = false
    var onRingTap: () -> Void = {}

    @State private var animatedVerified: Double = 0
    @State private var animatedPublished: Double = 0

    private var snapshot: SessionClosingMetricsSnapshot {
        SessionClosingMetricsSnapshot.compute(from: sessions, period: period)
    }

    private var outerDiameter: CGFloat { compact ? 64 : 86 }
    private var innerDiameter: CGFloat { compact ? 42 : 58 }
    private var ringLineWidth: CGFloat { compact ? 5 : 6 }
    private var ringFrame: CGFloat { compact ? 78 : 112 }
    private var countFontSize: CGFloat { compact ? 12 : 14 }

    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            ZStack {
                SessionClosingMetricRing(
                    progress: animatedVerified,
                    trackColor: SessionClosingMetricRingStyle.verifiedTrack,
                    progressColor: SessionClosingMetricRingStyle.verifiedProgress,
                    lineWidth: ringLineWidth,
                    diameter: outerDiameter
                )
                SessionClosingMetricRing(
                    progress: animatedPublished,
                    trackColor: SessionClosingMetricRingStyle.publishedTrack,
                    progressColor: SessionClosingMetricRingStyle.publishedProgress,
                    lineWidth: ringLineWidth,
                    diameter: innerDiameter
                )

                Text("\(snapshot.totalCount)")
                    .font(.system(size: countFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(compact ? 2 : 8)
            .frame(width: ringFrame, height: ringFrame)
            .contentShape(Rectangle())
            .onTapGesture(perform: onRingTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ringAccessibilitySummary)
            .accessibilityHint("Opens session history")
            .accessibilityAddTraits(.isButton)

            HStack(spacing: compact ? 10 : 16) {
                SessionClosingMetricLegendItem(
                    color: SessionClosingMetricRingStyle.verifiedProgress,
                    title: "Verified",
                    percent: Int((snapshot.verifiedFraction * 100).rounded())
                )
                SessionClosingMetricLegendItem(
                    color: SessionClosingMetricRingStyle.publishedProgress,
                    title: "Published",
                    percent: Int((snapshot.publishedFraction * 100).rounded())
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            resetProgressToZero()
            if isRevealed {
                growRings(to: snapshot)
            }
        }
        .onChange(of: isRevealed) { revealed in
            if revealed {
                growRings(to: snapshot)
            } else {
                resetProgressToZero()
            }
        }
        .onChange(of: sessions) { _ in
            guard isRevealed else { return }
            growRings(to: snapshot)
        }
        .onChange(of: period) { _ in
            guard isRevealed else { return }
            growRings(to: snapshot)
        }
    }

    private var ringAccessibilitySummary: String {
        let pct = { (value: Double) in Int((value * 100).rounded()) }
        return "\(snapshot.totalCount) sessions, \(period.label). Verified \(pct(snapshot.verifiedFraction)) percent. Published \(pct(snapshot.publishedFraction)) percent."
    }

    private func resetProgressToZero() {
        animatedVerified = 0
        animatedPublished = 0
    }

    private func growRings(to target: SessionClosingMetricsSnapshot) {
        resetProgressToZero()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.95, dampingFraction: 0.72)) {
                animatedVerified = target.verifiedFraction
                animatedPublished = target.publishedFraction
            }
        }
    }
}

private enum SessionClosingMetricRingStyle {
    static let verifiedTrack = Color(red: 0.08, green: 0.38, blue: 0.22)
    static let verifiedProgress = Color(red: 0.28, green: 0.92, blue: 0.48)
    static let publishedTrack = Color(red: 0.06, green: 0.08, blue: 0.14)
    static let publishedProgress = Color(red: 0.32, green: 0.52, blue: 0.95)
}

private struct SessionClosingMetricRing: View {
    let progress: Double
    let trackColor: Color
    let progressColor: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor.opacity(0.55), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct SessionClosingMetricLegendItem: View {
    let color: Color
    let title: String
    let percent: Int

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Text("\(percent)%")
                .font(.caption.bold())
                .foregroundColor(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}
