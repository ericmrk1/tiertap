import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BankrollView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showResetSheet = false
    @State private var resetEntryText = ""
    #if os(iOS)
    @State private var isShareSheetPresented = false
    @State private var shareURL: URL?
    #endif

    private var sessionsWithWinLoss: [Session] {
        store.sessions.filter { $0.winLoss != nil }.sorted { $0.startTime < $1.startTime }
    }

    private var lastResetDate: Date? {
        settingsStore.bankrollResets.last?.date
    }

    private var lastResetValue: Int {
        settingsStore.bankrollResets.last?.value ?? settingsStore.bankroll
    }

    /// Current total: baseline (last reset or settings bankroll) + sum of session P&L after that date.
    private var currentTotal: Int {
        let after = lastResetDate ?? Date.distantPast
        let sum = sessionsWithWinLoss
            .filter { $0.startTime >= after }
            .compactMap(\.winLoss)
            .reduce(0, +)
        return lastResetValue + sum
    }

    /// Timeline points (date, bankroll) and history rows built in one pass.
    private var bankrollTimeline: [(date: Date, value: Int)] {
        let (points, _) = buildTimelineAndHistory()
        return points
    }

    private var historyEntries: [(date: Date, isReset: Bool, title: String, bankrollAfter: Int?)] {
        let (_, entries) = buildTimelineAndHistory()
        return entries.sorted { $0.date > $1.date }
    }

    private func buildTimelineAndHistory() -> (points: [(Date, Int)], entries: [(date: Date, isReset: Bool, title: String, bankrollAfter: Int?)]) {
        enum Event: Comparable {
            case reset(BankrollResetEvent)
            case session(Session)
            var date: Date {
                switch self {
                case .reset(let e): return e.date
                case .session(let s): return s.startTime
                }
            }
            static func < (l: Event, r: Event) -> Bool { l.date < r.date }
        }
        var events: [Event] = []
        events += settingsStore.bankrollResets.map { .reset($0) }
        events += sessionsWithWinLoss.map { .session($0) }
        events.sort(by: { $0.date < $1.date })

        guard !events.isEmpty else {
            let b = settingsStore.bankroll
            return ([(Date(), b)], [])
        }

        let lastReset = settingsStore.bankrollResets.last
        let baselineDate = lastReset?.date ?? Date.distantPast
        let sessionsBeforeBaseline = sessionsWithWinLoss.filter { $0.startTime < baselineDate }
        let initialRunning = lastResetValue - sessionsBeforeBaseline.compactMap(\.winLoss).reduce(0, +)

        var points: [(Date, Int)] = []
        var entries: [(date: Date, isReset: Bool, title: String, bankrollAfter: Int?)] = []
        var running = initialRunning

        for event in events {
            switch event {
            case .reset(let e):
                running = e.value
                points.append((e.date, running))
                entries.append((e.date, true, "Bankroll reset to \(settingsStore.currencySymbol)\(e.value)", nil))
            case .session(let s):
                running += s.winLoss ?? 0
                points.append((s.startTime, running))
                let wl = s.winLoss ?? 0
                let wlStr = wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))"
                entries.append((s.startTime, false, "\(s.casino) · \(wlStr)", running))
            }
        }
        return (points, entries)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        totalCard
                        resetButton
                        graphCard
                        historySection
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Bankroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    if bankrollTimeline.count > 1 {
                        Button {
                            shareBankrollGraph()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                        }
                        .accessibilityLabel("Share bankroll graph")
                    }
                }
                #endif
            }
            .adaptiveSheet(isPresented: $showResetSheet) {
                resetSheet
            }
            .onAppear {
                BankrollDatabase.shared.open()
                BankrollDatabase.shared.syncSessions(store.sessions)
            }
            #if os(iOS)
            .adaptiveSheet(isPresented: $isShareSheetPresented) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .onChange(of: isShareSheetPresented) { newValue in
                if !newValue, let url = shareURL {
                    try? FileManager.default.removeItem(at: url)
                    shareURL = nil
                }
            }
            #endif
        }
    }

    #if os(iOS)
    private func shareBankrollGraph() {
        let card = BankrollGraphShareCard(
            points: bankrollTimeline,
            gradient: settingsStore.primaryGradient,
            currentTotal: currentTotal,
            currencySymbol: settingsStore.currencySymbol
        )
        guard let image = renderBankrollCardToImage(card) else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        let name = "TierTapBankroll\(df.string(from: Date())).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return }
        shareURL = url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isShareSheetPresented = true
        }
    }

    @MainActor
    private func renderBankrollCardToImage(_ view: BankrollGraphShareCard) -> UIImage? {
        let width = UIScreen.main.bounds.width * 0.9
        let height: CGFloat = 320
        let wrapped = view
            .padding()
            .frame(width: width, height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = UIScreen.main.scale
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

    private var totalCard: some View {
        VStack(spacing: 8) {
            L10nText("Current Bankroll")
                .font(.subheadline.bold())
                .foregroundColor(.white.opacity(0.9))
            Text("\(settingsStore.currencySymbol)\(currentTotal)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemGray6).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resetButton: some View {
        Button {
            resetEntryText = "\(settingsStore.bankroll)"
            showResetSheet = true
        } label: {
            LocalizedLabel(title: "Reset Bankroll", systemImage: "arrow.counterclockwise")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.25))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedLabel(title: "Bankroll Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.white)

            if bankrollTimeline.count <= 1 {
                L10nText("Complete sessions to see your bankroll trend.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                BankrollLineChart(points: bankrollTimeline, gradient: settingsStore.primaryGradient)
                    .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedLabel(title: "History", systemImage: "list.bullet")
                .font(.headline)
                .foregroundColor(.white)

            if historyEntries.isEmpty {
                L10nText("No bankroll history yet.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(historyEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 72, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                if entry.isReset {
                                    L10nText("Settings bankroll updated to this value.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                } else if let after = entry.bankrollAfter {
                                    Text("Bankroll after: \(settingsStore.currencySymbol)\(after)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(entry.isReset ? Color.orange.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resetSheet: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 20) {
                    L10nText("Enter new bankroll value. This updates the bankroll in Settings and starts tracking from this value.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextField("Bankroll (\(settingsStore.currencySymbol))", text: $resetEntryText)
                        .textFieldStyle(DarkTextFieldStyle())
                        .keyboardType(.numberPad)
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .localizedNavigationTitle("Reset Bankroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showResetSheet = false
                    }
                    .foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") {
                        if let v = Int(resetEntryText.filter { $0.isNumber }), v >= 0 {
                            settingsStore.resetBankroll(to: v)
                            showResetSheet = false
                        }
                    }
                    .foregroundColor((Int(resetEntryText.filter { $0.isNumber }) ?? 0) >= 0 ? .green : .gray)
                    .disabled(Int(resetEntryText.filter { $0.isNumber }) == nil)
                }
            }
        }
    }
}

/// Card view used when rendering the bankroll graph for the share sheet (title + total + chart).
struct BankrollGraphShareCard: View {
    let points: [(date: Date, value: Int)]
    let gradient: LinearGradient
    let currentTotal: Int
    let currencySymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    L10nText("Bankroll Over Time")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Current: \(currencySymbol)\(currentTotal)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
            }
            if points.count > 1 {
                BankrollLineChart(points: points, gradient: gradient)
                    .frame(height: 180)
            } else {
                L10nText("Add sessions to see your bankroll trend.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Line chart for bankroll (date, value) points. Uses same style as AnalyticsView LineChart.
struct BankrollLineChart: View {
    let points: [(date: Date, value: Int)]
    let gradient: LinearGradient

    private var values: [Double] {
        points.map { Double($0.value) }
    }

    var body: some View {
        LineChart(points: values, gradient: gradient, showValueLabels: true)
    }
}
