import SwiftUI

/// Three horizontal stat chips for TierTap Plus pack metrics (Account / Paywall).
struct TierTapPlusTokenStatBubbles: View {
    let packBalance: Int
    let lifetimePurchased: Int
    let packUsage: Int
    /// Smaller type for dense layouts (e.g. subscription paywall).
    var compact: Bool = false

    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            bubble(title: "Pack Balance", value: packBalance)
            bubble(title: "Lifetime", value: lifetimePurchased)
            bubble(title: "Pack Usage", value: packUsage)
        }
    }

    private func bubble(title: String, value: Int) -> some View {
        VStack(spacing: compact ? 3 : 4) {
            Text(L10n.tr(title, language: appLanguage))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .lineLimit(2)
            Text(value.formatted(.number.grouping(.automatic)))
                .font(compact ? .caption.weight(.bold) : .caption.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 6 : 8)
        .padding(.horizontal, 3)
        .background(Color.black.opacity(0.22))
        .cornerRadius(10)
    }
}
