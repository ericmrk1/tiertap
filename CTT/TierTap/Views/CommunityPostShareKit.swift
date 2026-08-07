import SwiftUI
import UIKit

#if os(iOS)

// MARK: - Share payloads

struct CommunityPostShareMediaItem: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

// MARK: - Caption + export

enum CommunityPostShareExporter {
    /// Short caption for Twitter / Messages / etc. Image carries the visual detail.
    static func caption(
        for item: TableGamePostRow,
        currencySymbol: String,
        anonymousLabel: String = "Anonymous"
    ) -> String {
        let casino = item.location ?? item.session_details?.casino ?? "a casino"
        let game = item.game ?? item.session_details?.game ?? "table games"
        let name = item.feedScreenName ?? anonymousLabel
        var lines: [String] = [
            "\(name) on TierTap Community — \(casino) · \(game)"
        ]

        if let comment = item.session_details?.comment?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !comment.isEmpty {
            lines.append("\"\(comment)\"")
        }

        if let wl = item.metrics?.net_win_loss {
            let amount = "\(currencySymbol)\(abs(wl).formatted(.number.grouping(.automatic)))"
            lines.append(wl >= 0 ? "Net +\(amount)" : "Net −\(amount)")
        }

        lines.append("#TierTap")
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func renderShareImage(
        item: TableGamePostRow,
        currencySymbol: String,
        gradient: LinearGradient,
        avatarImage: UIImage?,
        anonymousLabel: String = "Anonymous"
    ) -> UIImage? {
        let width = ShareImageExportQuality.wideCardWidthPoints
        let card = CommunityPostShareCard(
            item: item,
            currencySymbol: currencySymbol,
            gradient: gradient,
            avatarImage: avatarImage,
            anonymousLabel: anonymousLabel,
            cardWidth: width
        )
        // Height is content-driven; give ImageRenderer room then crop emptiness.
        let proposedHeight: CGFloat = 720
        let wrapped = card.frame(width: width)

        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = ShareImageExportQuality.imageRendererScale
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            return renderer.uiImage
        } else {
            let controller = UIHostingController(rootView: wrapped)
            let target = CGSize(width: width, height: proposedHeight)
            controller.view.bounds = CGRect(origin: .zero, size: target)
            controller.view.backgroundColor = .clear
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let fitting = controller.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
            let size = CGSize(width: width, height: max(320, min(proposedHeight, fitting.height)))
            controller.view.bounds = CGRect(origin: .zero, size: size)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }

    static func loadAvatarImage(from url: URL?) async -> UIImage? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Share card (feed-matching look)

struct CommunityPostShareCard: View {
    let item: TableGamePostRow
    let currencySymbol: String
    let gradient: LinearGradient
    let avatarImage: UIImage?
    var anonymousLabel: String = "Anonymous"
    var cardWidth: CGFloat = 400

    private var metrics: TableGamePostMetrics? { item.metrics }

    private var currencySymbolForMetrics: String {
        metrics?.currency_symbol ?? currencySymbol
    }

    private var displayScreenName: String {
        item.feedScreenName ?? anonymousLabel
    }

    private var relativeTimestamp: String {
        CommunityFeedFormatting.relativeTimestamp(from: item.created_at)
    }

    private var betDifferentialPercent: Double? {
        guard
            let rated = metrics?.avg_bet_rated,
            let actual = metrics?.avg_bet_actual,
            rated != 0
        else { return nil }
        return (Double(rated - actual) / Double(rated)) * 100.0
    }

    private var betDifferentialColor: Color {
        guard let diff = betDifferentialPercent else { return Color.white.opacity(0.1) }
        if diff > 0 { return Color.green.opacity(0.8) }
        if diff < 0 { return Color.red.opacity(0.8) }
        return Color.gray.opacity(0.6)
    }

    private var tiersPerHourColor: Color {
        guard let tiers = metrics?.tiers_per_hour else { return Color.white.opacity(0.12) }
        return tiers >= 0 ? Color.green.opacity(0.75) : Color.red.opacity(0.75)
    }

    private var tierDelta: Int? {
        guard
            let start = metrics?.starting_tier_points,
            let end = metrics?.ending_tier_points
        else { return nil }
        return end - start
    }

    private var tierDeltaColor: Color {
        guard let delta = tierDelta else { return Color.white.opacity(0.12) }
        if delta > 0 { return Color.green.opacity(0.75) }
        if delta < 0 { return Color.red.opacity(0.75) }
        return Color.gray.opacity(0.6)
    }

    var body: some View {
        let casinoName = item.location ?? item.session_details?.casino ?? "Unknown casino"
        let gameName = item.game ?? item.session_details?.game ?? "Unknown game"
        let comment = item.session_details?.comment?.trimmingCharacters(in: .whitespacesAndNewlines)

        ZStack {
            gradient
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Community")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image("TierTapLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("TierTap")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        avatarView

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(displayScreenName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(relativeTimestamp)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.55))
                                Spacer(minLength: 0)
                            }

                            if let comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(8)
                            }

                            Text(casinoName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(2)

                            Text(gameName)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)

                            metricChips
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(18)
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var avatarView: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                    Image(systemName: item.feedScreenName == nil ? "eye.slash" : "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var metricChips: some View {
        CommunityFeedChipFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            if let wl = metrics?.net_win_loss {
                let sym = currencySymbolForMetrics
                chip(
                    text: wl >= 0 ? "Net +\(sym)\(wl)" : "Net -\(sym)\(abs(wl))",
                    fill: wl >= 0 ? Color.green.opacity(0.75) : Color.red.opacity(0.75)
                )
            }

            if let tc = metrics?.total_comp, tc > 0, let ev = metrics?.expected_value {
                let sym = currencySymbolForMetrics
                chip(
                    text: ev >= 0 ? "EV +\(sym)\(ev)" : "EV -\(sym)\(abs(ev))",
                    fill: ev >= 0 ? Color.teal.opacity(0.75) : Color.orange.opacity(0.75)
                )
            }

            if let cc = metrics?.comp_count, cc > 0 {
                let sym = currencySymbolForMetrics
                let countLabel = cc == 1 ? "1 comp" : "\(cc) comps"
                let label: String = {
                    if let cv = metrics?.comp_value_total {
                        return "\(countLabel) · \(sym)\(cv) est."
                    }
                    return countLabel
                }()
                chip(text: label, fill: Color.purple.opacity(0.7))
            }

            if let fp = metrics?.total_free_play, fp > 0 {
                let sym = currencySymbolForMetrics
                chip(text: "Free play \(sym)\(fp)", fill: Color.orange.opacity(0.8))
            }

            if let tiers = metrics?.tiers_per_hour {
                chip(text: String(format: "%.1f pts/hr", tiers), fill: tiersPerHourColor)
            }

            if let diff = betDifferentialPercent {
                chip(
                    text: "Rating Diff " + String(format: "%+.0f%%", diff),
                    fill: betDifferentialColor
                )
            } else if metrics?.avg_bet_actual != nil || metrics?.avg_bet_rated != nil {
                chipOutline(text: "Rating Diff N/A")
            }

            if let delta = tierDelta {
                let sign = delta >= 0 ? "+" : ""
                chip(text: "\(sign)\(delta) pts", fill: tierDeltaColor)
            }
        }
    }

    private func chip(text: String, fill: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }

    private func chipOutline(text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Preview sheet

struct CommunityPostSharePreviewSheet: View {
    let image: UIImage
    let caption: String
    let gradient: LinearGradient
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                gradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Share Preview")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Image + caption open in the system share sheet for X, Instagram, Messages, and more.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )

                            Text(caption)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Button(action: onShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Share Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(gradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundColor(.green)
                }
            }
        }
    }
}

#endif
