import SwiftUI
import UIKit

struct TierTapWrappedView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    #if os(iOS)
    @State private var shareItem: ShareableImageItem?
    @State private var shareStatus: String?
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if let summary = TierTapProductEnhancements.currentWrappedSummary(sessions: store.sessions) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TierTap Wrapped")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text(summary.monthLabel)
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text("A recap of your logged play — tracking quality, not a nudge to play more.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                wrappedStat(title: "Sessions", value: "\(summary.sessionCount)")
                                wrappedStat(title: "Tier points", value: "\(summary.tierPointsEarned)")
                                wrappedStat(title: "Cash net", value: signed(summary.cashNet))
                                wrappedStat(title: "True EV", value: signed(summary.expectedValue))
                                wrappedStat(title: "Hours", value: String(format: "%.1f", summary.hoursPlayed))
                                if let mood = summary.topMood {
                                    wrappedStat(title: "Top mood", value: mood.label)
                                }
                            }

                            if let game = summary.bestGameForTiers, let tph = summary.bestGameTiersPerHour {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Best game for tiers")
                                        .font(.caption.bold())
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(game) · \(String(format: "%.1f", tph)) tiers/hour")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(12)
                            }

                            if let biggest = summary.biggestEVSession {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Biggest EV session")
                                        .font(.caption.bold())
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(signed(biggest))
                                        .font(.title3.bold())
                                        .foregroundColor(biggest >= 0 ? .green : .red)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(12)
                            }

                            #if os(iOS)
                            Button {
                                shareWrapped(summary)
                            } label: {
                                Label("Share Wrapped", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)

                            if let shareStatus {
                                Text(shareStatus)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            #endif
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.7))
                        Text("No monthly recap yet")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Close a few sessions this month and your Wrapped will appear here.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Monthly Wrapped")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                #if os(iOS)
                if TierTapProductEnhancements.currentWrappedSummary(sessions: store.sessions) != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let summary = TierTapProductEnhancements.currentWrappedSummary(sessions: store.sessions) {
                                shareWrapped(summary)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundColor(.white)
                    }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            #if os(iOS)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }
            #endif
        }
    }

    private func wrappedStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.28))
        .cornerRadius(12)
    }

    private func signed(_ value: Int) -> String {
        let s = settingsStore.currencySymbol
        return value >= 0 ? "+\(s)\(value)" : "-\(s)\(abs(value))"
    }

    #if os(iOS)
    @MainActor
    private func shareWrapped(_ summary: TierTapProductEnhancements.MonthlyWrappedSummary) {
        let card = TierTapWrappedShareCard(
            summary: summary,
            currencySymbol: settingsStore.currencySymbol,
            gradient: settingsStore.primaryGradient
        )
        guard let image = renderWrappedCard(card) else {
            shareStatus = "Couldn't render share image."
            return
        }
        shareItem = ShareableImageItem(image: image)
    }

    @MainActor
    private func renderWrappedCard(_ view: TierTapWrappedShareCard) -> UIImage? {
        let width = ShareImageExportQuality.wideCardWidthPoints
        let height: CGFloat = 520
        let wrapped = view.frame(width: width, height: height)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = ShareImageExportQuality.imageRendererScale
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            return renderer.uiImage
        } else {
            let controller = UIHostingController(rootView: wrapped)
            controller.view.bounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            controller.view.backgroundColor = .clear
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }
    #endif
}

#if os(iOS)
private struct TierTapWrappedShareCard: View {
    let summary: TierTapProductEnhancements.MonthlyWrappedSummary
    let currencySymbol: String
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            gradient
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TierTap Wrapped")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text(summary.monthLabel)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("TierTap")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.7))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    shareStat("Sessions", "\(summary.sessionCount)")
                    shareStat("Tier pts", "\(summary.tierPointsEarned)")
                    shareStat("Cash net", signed(summary.cashNet))
                    shareStat("True EV", signed(summary.expectedValue))
                    shareStat("Hours", String(format: "%.1f", summary.hoursPlayed))
                    if let mood = summary.topMood {
                        shareStat("Top mood", mood.label)
                    }
                }

                if let game = summary.bestGameForTiers, let tph = summary.bestGameTiersPerHour {
                    Text("Best game · \(game) · \(String(format: "%.1f", tph)) tph")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shareStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.28))
        .cornerRadius(10)
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(currencySymbol)\(value)" : "-\(currencySymbol)\(abs(value))"
    }
}
#endif
