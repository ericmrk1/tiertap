import SwiftUI

/// Ambient loyalty tier goal progress for Home and Wallet.
struct LoyaltyTierGoalRingView: View {
    let card: RewardWalletCard
    var compact: Bool = false
    /// When set, the card uses a fixed width (for horizontal carousels on Home).
    var carouselWidth: CGFloat? = nil

    private var progress: Double {
        card.tierGoalProgress ?? 0
    }

    private var remaining: Int? {
        card.pointsRemainingToTierGoal
    }

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: compact ? 5 : 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: compact ? 5 : 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(compact ? .caption2.bold() : .caption.bold())
                        .foregroundColor(.white)
                }
            }
            .frame(width: compact ? 40 : 64, height: compact ? 40 : 64)

            VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                Text(card.rewardProgram.isEmpty ? "Loyalty goal" : card.rewardProgram)
                    .font(compact ? .caption2.bold() : .subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let label = card.tierGoalLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.cyan.opacity(0.95))
                }
                if let goal = card.tierGoalPoints {
                    let current = card.parsedCurrentTierPoints.map(String.init) ?? (card.currentTier.isEmpty ? "—" : card.currentTier)
                    Text("\(current) / \(goal) pts")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let remaining {
                    Text(remaining == 0 ? "Goal reached" : "\(remaining) pts to go")
                        .font(.caption2)
                        .foregroundColor(remaining == 0 ? .green : .white.opacity(0.65))
                }
            }
            // Only stretch when a fixed carousel width is requested; otherwise hug content (no trailing blank).
            if carouselWidth != nil {
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 8 : 14)
        .frame(width: carouselWidth, alignment: .leading)
        .fixedSize(horizontal: carouselWidth == nil, vertical: true)
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Horizontal scroller of every wallet card that has a tier goal — shown on Home under Tap Level.
struct HomeRewardsTierGoalsSection: View {
    let cards: [RewardWalletCard]
    var autoScrollEnabled: Bool = true
    var onSelectCard: ((RewardWalletCard) -> Void)? = nil

    @State private var isExpanded = true

    private let cardWidth: CGFloat = 200
    private let cardSpacing: CGFloat = 8
    /// Extra gap between the last and first tier goal when the ticker loops.
    private let loopGap: CGFloat = 56
    /// Ticker strip height — slightly taller than the old 56pt cap to avoid clipping bottom text.
    private let tickerRowHeight: CGFloat = 66

    /// Highest current tier points first (left-justified in the scroller).
    private var goalCards: [RewardWalletCard] {
        cards
            .filter(\.hasTierGoal)
            .sorted { lhs, rhs in
                let l = lhs.parsedCurrentTierPoints ?? 0
                let r = rhs.parsedCurrentTierPoints ?? 0
                if l != r { return l > r }
                let lg = lhs.tierGoalPoints ?? 0
                let rg = rhs.tierGoalPoints ?? 0
                return lg > rg
            }
    }

    /// Changes when cards are edited so the ticker rebuilds instead of showing stale tiles.
    private var cardsRevision: String {
        goalCards.map { card in
            [
                card.id.uuidString,
                card.rewardProgram,
                card.currentTier,
                String(card.tierGoalPoints ?? 0),
                String(card.parsedCurrentTierPoints ?? 0)
            ].joined(separator: ";")
        }.joined(separator: "|")
    }

    var body: some View {
        if !goalCards.isEmpty {
            VStack(alignment: .leading, spacing: isExpanded ? 6 : 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                        Text("Tier Goals")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                        Text("\(goalCards.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.45))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tier Goals")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

                if isExpanded {
                    if autoScrollEnabled {
                        HomeTierGoalsTickerStrip(
                            cards: goalCards,
                            cardsRevision: cardsRevision,
                            cardWidth: cardWidth,
                            cardSpacing: cardSpacing,
                            loopGap: loopGap,
                            onSelectCard: onSelectCard
                        )
                        .id(cardsRevision)
                        .frame(height: tickerRowHeight)
                    } else {
                        manualGoalsScroll
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, isExpanded ? 8 : 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.25), value: isExpanded)
            .accessibilityHint(autoScrollEnabled ? "Tier goal ticker is scrolling." : "Swipe for more tier goals.")
        }
    }

    private var manualGoalsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(goalCards) { card in
                    tierGoalCardButton(card)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func tierGoalCardButton(_ card: RewardWalletCard) -> some View {
        if let onSelectCard {
            Button {
                onSelectCard(card)
            } label: {
                LoyaltyTierGoalRingView(card: card, compact: true, carouselWidth: cardWidth)
            }
            .buttonStyle(.plain)
        } else {
            LoyaltyTierGoalRingView(card: card, compact: true, carouselWidth: cardWidth)
        }
    }
}

/// Auto-scrolling tier-goal ticker; scrolls left to right with a duplicated strip for seamless looping.
private struct HomeTierGoalsTickerStrip: View {
    let cards: [RewardWalletCard]
    let cardsRevision: String
    let cardWidth: CGFloat
    let cardSpacing: CGFloat
    let loopGap: CGFloat
    var onSelectCard: ((RewardWalletCard) -> Void)? = nil

    @State private var scrollOffset: CGFloat = 0

    private let pointsPerSecond: CGFloat = 22
    private let tickerTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var stripWidth: CGFloat {
        let count = CGFloat(cards.count)
        guard count > 0 else { return 0 }
        return count * cardWidth + max(0, count - 1) * cardSpacing
    }

    private var loopWidth: CGFloat {
        guard stripWidth > 0 else { return 0 }
        return stripWidth + loopGap
    }

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: loopGap) {
                tickerRow(copyIndex: 0)
                tickerRow(copyIndex: 1)
            }
            .offset(x: scrollOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 18)
                Rectangle().fill(Color.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 18)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 10)
        }
        .clipped()
        .onReceive(tickerTimer) { _ in
            let width = loopWidth
            guard width > 0 else { return }
            scrollOffset += pointsPerSecond / 60.0
            while scrollOffset >= width {
                scrollOffset -= width
            }
        }
        .onChange(of: cardsRevision) { _ in
            scrollOffset = 0
        }
        .onAppear {
            scrollOffset = 0
        }
    }

    private func tickerRow(copyIndex: Int) -> some View {
        HStack(spacing: cardSpacing) {
            ForEach(cards) { card in
                Group {
                    if let onSelectCard {
                        Button {
                            onSelectCard(card)
                        } label: {
                            LoyaltyTierGoalRingView(card: card, compact: true, carouselWidth: cardWidth)
                        }
                        .buttonStyle(.plain)
                    } else {
                        LoyaltyTierGoalRingView(card: card, compact: true, carouselWidth: cardWidth)
                    }
                }
                .id("\(copyIndex)-\(card.id.uuidString)-\(cardsRevision)")
            }
        }
    }
}
