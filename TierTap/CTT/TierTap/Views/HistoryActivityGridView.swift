import SwiftUI

/// What each day cell aggregates for color (sign) and shading (session volume).
enum HistoryGridMetricMode: String, CaseIterable, Identifiable {
    case profitLoss
    case comps
    case tierChanges

    var id: String { rawValue }

    var sliderLabel: String {
        switch self {
        case .profitLoss: return "Profit & Loss"
        case .comps: return "Comps"
        case .tierChanges: return "Tier Changes"
        }
    }

    func contribution(from session: Session) -> Int? {
        switch self {
        case .profitLoss: return session.winLoss
        case .comps: return session.totalComp
        case .tierChanges: return session.tierPointsEarned
        }
    }
}

private struct HistoryDayDetail {
    let date: Date
    let sessions: [Session]
    let sessionCount: Int
    let profitLossNet: Int
    let compsNet: Int
    let tierPointsNet: Int
    let hasProfitLossData: Bool
    let hasTierData: Bool
}

/// GitHub-style activity grid: six months per page in one row; green/red by metric sign.
struct HistoryActivityGridView: View {
    let sessions: [Session]
    @Binding var metricMode: HistoryGridMetricMode

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var pressedDay: Date?
    /// 0 = most recent six months; higher values go further into the past.
    @State private var periodOffset: Int = 0
    #if os(iOS)
    @State private var sharePreviewItem: ShareableImageItem?
    @State private var shareSheetItem: ShareableImageItem?
    @State private var pendingShareImage: UIImage?
    @State private var shouldPresentShareAfterPreviewDismiss = false
    #endif

    private let calendar = Calendar.current

    private var aggregatesByDay: [Date: HistoryDayAggregate] {
        HistoryActivityGridEngine.aggregates(sessions: sessions, metricMode: metricMode, calendar: calendar)
    }

    private var gridHeightEstimate: CGFloat {
        let layout = HistoryActivityGridEngine.layout(
            for: HistoryActivityGridEngine.preferredLayoutWidth(),
            periodOffset: periodOffset,
            calendar: calendar
        )
        return HistoryActivityGridEngine.gridContentHeight(cellSize: layout.cellSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            shareHeaderRow
                .padding(.horizontal, 16)
            #endif

            periodNavigationHeader
                .padding(.horizontal, 16)

            gridBandsSection
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: gridHeightEstimate)
                .simultaneousGesture(periodSwipeGesture)

            if let pressedDay {
                dayDetailPanel(for: pressedDay)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.horizontal, 16)
            }

            metricModeSlider
                .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: pressedDay)
        .animation(.easeInOut(duration: 0.2), value: periodOffset)
        #if os(iOS)
        .sheet(item: $sharePreviewItem, onDismiss: {
            guard shouldPresentShareAfterPreviewDismiss, let image = pendingShareImage else {
                pendingShareImage = nil
                return
            }
            shouldPresentShareAfterPreviewDismiss = false
            pendingShareImage = nil
            shareSheetItem = ShareableImageItem(image: image)
        }) { preview in
            HistoryGridSharePreviewSheet(
                image: preview.image,
                gradient: settingsStore.primaryGradient,
                onShare: {
                    pendingShareImage = preview.image
                    shouldPresentShareAfterPreviewDismiss = true
                    sharePreviewItem = nil
                },
                onClose: {
                    shouldPresentShareAfterPreviewDismiss = false
                    pendingShareImage = nil
                    sharePreviewItem = nil
                }
            )
        }
        .sheet(item: $shareSheetItem) { item in
            ShareSheet(items: [item.image])
        }
        #endif
    }

    #if os(iOS)
    private var shareHeaderRow: some View {
        HStack {
            Spacer()
            Button(action: beginSharePreview) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .disabled(sessions.isEmpty)
            .opacity(sessions.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Share session grid")
        }
    }

    @MainActor
    private func beginSharePreview() {
        guard let image = HistoryActivityGridShareExporter.renderImage(
            sessions: sessions,
            metricMode: metricMode,
            gradient: settingsStore.primaryGradient,
            periodOffset: periodOffset
        ) else { return }
        shareSheetItem = nil
        sharePreviewItem = ShareableImageItem(image: image)
    }
    #endif

    private var periodNavigationHeader: some View {
        HStack(spacing: 12) {
            Button(action: showOlderPeriod) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous six months")

            VStack(spacing: 2) {
                Text(HistoryActivityGridEngine.yearLabel(forPeriodOffset: periodOffset, calendar: calendar))
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text(HistoryActivityGridEngine.monthRangeCaption(forPeriodOffset: periodOffset, calendar: calendar))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)

            Button(action: showNewerPeriod) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white.opacity(periodOffset == 0 ? 0.35 : 0.9))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(periodOffset == 0)
            .accessibilityLabel("Next six months")
        }
    }

    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.width < -40 {
                    showOlderPeriod()
                } else if value.translation.width > 40 {
                    showNewerPeriod()
                }
            }
    }

    private func showOlderPeriod() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pressedDay = nil
            periodOffset += 1
        }
    }

    private func showNewerPeriod() {
        guard periodOffset > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            pressedDay = nil
            periodOffset -= 1
        }
    }

    @ViewBuilder
    private var gridBandsSection: some View {
        let layoutWidth = HistoryActivityGridEngine.preferredLayoutWidth()
        let layout = HistoryActivityGridEngine.layout(
            for: layoutWidth,
            periodOffset: periodOffset,
            calendar: calendar
        )
        if layout.bands.isEmpty {
            emptyGridPlaceholder
                .padding(.horizontal, 16)
        } else {
            HistoryActivityGridBandsView(
                layout: layout,
                aggregates: aggregatesByDay,
                pressedDay: pressedDay,
                onDayPressChanged: { day in
                    pressedDay = day
                },
                calendar: calendar
            )
        }
    }

    private var emptyGridPlaceholder: some View {
        Text("No session data for this metric in the selected range.")
            .font(.caption)
            .foregroundColor(.white.opacity(0.65))
            .padding(.top, 8)
    }

    private var metricModeSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metricMode.sliderLabel)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.85))
            Slider(value: metricModeIndex, in: 0...Double(HistoryGridMetricMode.allCases.count - 1), step: 1)
                .tint(.green)
            HStack {
                ForEach(Array(HistoryGridMetricMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    if index > 0 { Spacer(minLength: 4) }
                    Text(mode.sliderLabel)
                        .font(.caption2)
                        .foregroundColor(metricMode == mode ? .white : .white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private var metricModeIndex: Binding<Double> {
        Binding(
            get: {
                Double(HistoryGridMetricMode.allCases.firstIndex(of: metricMode) ?? 0)
            },
            set: { newValue in
                let index = Int(newValue.rounded())
                guard HistoryGridMetricMode.allCases.indices.contains(index) else { return }
                metricMode = HistoryGridMetricMode.allCases[index]
            }
        )
    }

    private func dayDetailPanel(for day: Date) -> some View {
        let detail = dayDetail(for: day)
        let sym = settingsStore.currencySymbol

        return VStack(alignment: .leading, spacing: 8) {
            Text(formattedDay(detail.date))
                .font(.subheadline.bold())
                .foregroundColor(.white)

            if detail.sessionCount == 0 {
                Text("No sessions on this day.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                HStack(spacing: 12) {
                    detailMetric(title: "Sessions", value: "\(detail.sessionCount)", emphasized: false)
                    detailMetric(
                        title: "P&L",
                        value: detail.hasProfitLossData ? signedCurrency(detail.profitLossNet, symbol: sym) : "—",
                        emphasized: metricMode == .profitLoss,
                        valueColor: colorForNet(detail.profitLossNet, hasData: detail.hasProfitLossData)
                    )
                    detailMetric(
                        title: "Comps",
                        value: signedCurrency(detail.compsNet, symbol: sym),
                        emphasized: metricMode == .comps,
                        valueColor: colorForNet(detail.compsNet, hasData: true)
                    )
                    detailMetric(
                        title: "Tier",
                        value: detail.hasTierData ? signedPoints(detail.tierPointsNet) : "—",
                        emphasized: metricMode == .tierChanges,
                        valueColor: colorForNet(detail.tierPointsNet, hasData: detail.hasTierData)
                    )
                }

                ForEach(detail.sessions) { session in
                    sessionLine(session, symbol: sym)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func detailMetric(title: String, value: String, emphasized: Bool, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(emphasized ? .green.opacity(0.95) : .white.opacity(0.55))
            Text(value)
                .font(.caption.bold())
                .foregroundColor(emphasized ? valueColor : .white.opacity(0.85))
        }
    }

    private func sessionLine(_ session: Session, symbol: String) -> some View {
        HStack(spacing: 6) {
            Text(session.casino)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Text("•")
                .font(.caption2)
                .foregroundColor(.gray)
            Text(session.game)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let wl = session.winLoss {
                Text(signedCurrency(wl, symbol: symbol))
                    .font(.caption2.bold())
                    .foregroundColor(wl >= 0 ? .green : .red)
            }
        }
    }

    private func dayDetail(for day: Date) -> HistoryDayDetail {
        let dayStart = calendar.startOfDay(for: day)
        let daySessions = sessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: dayStart) }
            .sorted { $0.startTime < $1.startTime }

        var profitLossNet = 0
        var hasProfitLossData = false
        var tierPointsNet = 0
        var hasTierData = false
        var compsNet = 0

        for session in daySessions {
            compsNet += session.totalComp
            if let wl = session.winLoss {
                profitLossNet += wl
                hasProfitLossData = true
            }
            if let tier = session.tierPointsEarned {
                tierPointsNet += tier
                hasTierData = true
            }
        }

        return HistoryDayDetail(
            date: dayStart,
            sessions: daySessions,
            sessionCount: daySessions.count,
            profitLossNet: profitLossNet,
            compsNet: compsNet,
            tierPointsNet: tierPointsNet,
            hasProfitLossData: hasProfitLossData,
            hasTierData: hasTierData
        )
    }

    private func colorForNet(_ value: Int, hasData: Bool) -> Color {
        guard hasData else { return .white.opacity(0.7) }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .white.opacity(0.85)
    }

    private func signedCurrency(_ value: Int, symbol: String) -> String {
        if value >= 0 { return "+\(symbol)\(value)" }
        return "-\(symbol)\(abs(value))"
    }

    private func signedPoints(_ value: Int) -> String {
        if value >= 0 { return "+\(value) pts" }
        return "\(value) pts"
    }

    private func formattedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func accessibilityLabel(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let aggregate = aggregatesByDay[calendar.startOfDay(for: day)]
        guard let aggregate, aggregate.sessionCount > 0 else {
            return "\(formatter.string(from: day)), no sessions"
        }
        return "\(formatter.string(from: day)), \(aggregate.sessionCount) session\(aggregate.sessionCount == 1 ? "" : "s"), net \(aggregate.netValue)"
    }
}

#if os(iOS)
struct HistoryGridSharePreviewSheet: View {
    let image: UIImage
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
                    Text("This is how your session grid will look when shared.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
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
            .navigationTitle("Share Grid")
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
