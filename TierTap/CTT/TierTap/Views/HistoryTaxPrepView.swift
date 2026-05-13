import SwiftUI
import Supabase
#if os(iOS)
import QuickLook
import UIKit
import UniformTypeIdentifiers
#endif

// MARK: - Session payload (excludes private notes; never sent to model)

private struct TaxPrepSessionLine: Encodable {
    let id: String
    let game: String
    let casino: String
    let startTime: String
    let endTime: String?
    let totalBuyIn: Int
    let cashOut: Int?
    let winLoss: Int?
    let totalComp: Int
    let compDollarsCredits: Int
    let compFoodBeverage: Int
    let hoursPlayed: Double
    let status: String
    let gameCategory: String?
    let sessionMood: String?
    let rewardsProgramName: String?
    let tierPointsStart: Int
    let tierPointsEnd: Int?
    let tierPointsEarned: Int?
    let avgBetActual: Int?
    let avgBetRated: Int?
    let isLive: Bool
    let buyInEventCount: Int
    let compEventCount: Int

    init(_ s: Session, dateFormatter: ISO8601DateFormatter) {
        id = s.id.uuidString
        game = s.game
        casino = s.casino
        startTime = dateFormatter.string(from: s.startTime)
        endTime = s.endTime.map { dateFormatter.string(from: $0) }
        totalBuyIn = s.totalBuyIn
        cashOut = s.cashOut
        winLoss = s.winLoss
        totalComp = s.totalComp
        compDollarsCredits = s.totalCompDollarsCredits
        compFoodBeverage = s.compEvents.filter { $0.kind == .foodBeverage }.reduce(0) { $0 + $1.amount }
        hoursPlayed = s.hoursPlayed
        status = s.status.rawValue
        gameCategory = s.gameCategory?.rawValue
        sessionMood = s.sessionMood?.rawValue
        rewardsProgramName = s.rewardsProgramName
        tierPointsStart = s.startingTierPoints
        tierPointsEnd = s.endingTierPoints
        tierPointsEarned = s.tierPointsEarned
        avgBetActual = s.avgBetActual
        avgBetRated = s.avgBetRated
        isLive = s.isLive
        buyInEventCount = s.buyInEvents.count
        compEventCount = s.compEvents.count
    }
}

private enum TaxPrepCSVExport {
    static func escapeField(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        var v = value.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes { v = "\"" + v + "\"" }
        return v
    }

    static func build(for sessions: [Session]) -> String {
        var lines: [String] = []
        let headers = [
            "id", "game", "casino", "start_time", "end_time", "duration_hours",
            "total_buy_in", "cash_out", "win_loss", "total_comp", "comp_dollars_credits", "comp_food_beverage",
            "status", "game_category", "session_mood", "rewards_program_name",
            "starting_tier_points", "ending_tier_points", "tier_points_earned",
            "avg_bet_actual", "avg_bet_rated", "is_live", "buy_in_event_count", "comp_event_count"
        ]
        lines.append(headers.joined(separator: ","))
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for s in sessions {
            let start = df.string(from: s.startTime)
            let end = s.endTime.map { df.string(from: $0) } ?? ""
            let foodComp = s.compEvents.filter { $0.kind == .foodBeverage }.reduce(0) { $0 + $1.amount }
            let rawFields: [String] = [
                s.id.uuidString,
                s.game,
                s.casino,
                start,
                end,
                String(format: "%.4f", s.hoursPlayed),
                String(s.totalBuyIn),
                s.cashOut.map { String($0) } ?? "",
                s.winLoss.map { String($0) } ?? "",
                String(s.totalComp),
                String(s.totalCompDollarsCredits),
                String(foodComp),
                s.status.rawValue,
                (s.gameCategory ?? .table).rawValue,
                s.sessionMood?.rawValue ?? "",
                s.rewardsProgramName ?? "",
                String(s.startingTierPoints),
                s.endingTierPoints.map { String($0) } ?? "",
                s.tierPointsEarned.map { String($0) } ?? "",
                s.avgBetActual.map { String($0) } ?? "",
                s.avgBetRated.map { String($0) } ?? "",
                s.isLive ? "true" : "false",
                String(s.buyInEvents.count),
                String(s.compEvents.count)
            ]
            lines.append(rawFields.map { escapeField($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

private enum TaxPrepW2GFallback {
    static func csv(for sessions: [Session]) -> String {
        let headers = [
            "session_id", "date_start", "date_end", "casino", "game", "gross_win_loss_app_units",
            "notes_tiertap_estimate_only"
        ]
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = [headers.joined(separator: ",")]
        for s in sessions {
            let row = [
                s.id.uuidString,
                df.string(from: s.startTime),
                s.endTime.map { df.string(from: $0) } ?? "",
                s.casino,
                s.game,
                s.winLoss.map { String($0) } ?? "",
                "TierTap estimate; not an official W-2G. Verify with casino records."
            ].map { TaxPrepCSVExport.escapeField($0) }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

private enum TaxPrepTurboTaxFallback {
    static func csv(for sessions: [Session]) -> String {
        let headers = ["date", "description", "amount", "category"]
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        var lines = [headers.joined(separator: ",")]
        for s in sessions {
            let wl = s.winLoss ?? 0
            let row = [
                df.string(from: s.startTime),
                "Gambling: \(s.casino) — \(s.game)",
                String(wl),
                "Gambling"
            ].map { TaxPrepCSVExport.escapeField($0) }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

private struct TaxExportFallback: Encodable {
    let taxYear: Int
    let disclaimer: String
    let sessions: [TaxPrepSessionLine]
}

private func taxPrepSessions(inCalendarYear year: Int, sessions: [Session]) -> [Session] {
    let cal = Calendar.current
    return sessions.filter { session in
        let yStart = cal.component(.year, from: session.startTime)
        if yStart == year { return true }
        if let end = session.endTime {
            return cal.component(.year, from: end) == year
        }
        return false
    }
}

private func taxPrepExtractJSONObject(from text: String) -> String {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("```") {
        s.removeFirst(3)
        if s.lowercased().hasPrefix("json") {
            s = String(s.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r = s.range(of: "```", options: .backwards) {
            s = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return s }
    return String(s[start...end])
}

private struct GeminiContentEnvelope: Decodable {
    let content: String
}

private func taxPrepDecodeContentOrRaw(_ raw: String) -> String {
    let slice = taxPrepExtractJSONObject(from: raw)
    if let data = slice.data(using: .utf8),
       let env = try? JSONDecoder().decode(GeminiContentEnvelope.self, from: data) {
        return env.content
    }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Tax optimization (structured JSON → UI)

private struct TaxOptimizationJSONRoot: Decodable {
    struct JSONSection: Decodable {
        let sectionTitle: String?
        let tips: [JSONTip]?
    }
    struct JSONTip: Decodable {
        let headline: String?
        let advice: String?
        let sessionExample: String?
    }
    let intro: String?
    let sections: [JSONSection]?
    let closingReminder: String?
}

private struct TaxOptimizationDisplayModel: Equatable {
    struct Section: Identifiable, Equatable {
        let id: UUID
        let title: String
        let tips: [Tip]
    }
    struct Tip: Identifiable, Equatable {
        let id: UUID
        let headline: String
        let advice: String
        let sessionExample: String?
    }
    var intro: String?
    var sections: [Section]
    var closingReminder: String?
}

private func taxOptimizationParseDisplayModel(from raw: String, language: AppLanguage) -> TaxOptimizationDisplayModel? {
    let slice = taxPrepExtractJSONObject(from: raw)
    guard let data = slice.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let root = try? decoder.decode(TaxOptimizationJSONRoot.self, from: data) else {
        return nil
    }
    var sections: [TaxOptimizationDisplayModel.Section] = []
    for js in root.sections ?? [] {
        let title = js.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { continue }
        let tips: [TaxOptimizationDisplayModel.Tip] = (js.tips ?? []).compactMap { jt in
            let h = jt.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let a = jt.advice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !h.isEmpty || !a.isEmpty else { return nil }
            let exRaw = jt.sessionExample?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ex = (exRaw?.isEmpty == true) ? nil : exRaw
            return TaxOptimizationDisplayModel.Tip(
                id: UUID(),
                headline: h.isEmpty ? L10n.tr("Key point", language: language) : h,
                advice: a,
                sessionExample: ex
            )
        }
        if !tips.isEmpty {
            sections.append(TaxOptimizationDisplayModel.Section(id: UUID(), title: title, tips: tips))
        }
    }
    guard !sections.isEmpty else { return nil }
    let introRaw = root.intro?.trimmingCharacters(in: .whitespacesAndNewlines)
    let closingRaw = root.closingReminder?.trimmingCharacters(in: .whitespacesAndNewlines)
    return TaxOptimizationDisplayModel(
        intro: (introRaw?.isEmpty == false) ? introRaw : nil,
        sections: sections,
        closingReminder: (closingRaw?.isEmpty == false) ? closingRaw : nil
    )
}

// MARK: - Persisted packet (Application Support, per calendar year)

private func taxPrepApplicationSupportBase() throws -> URL {
    let fm = FileManager.default
    guard let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        throw NSError(domain: "TaxPrep", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing Application Support directory."])
    }
    return app
        .appendingPathComponent("TierTap", isDirectory: true)
        .appendingPathComponent("TaxPrep", isDirectory: true)
}

private func taxPrepPersistedPacketDirectory(for year: Int, create: Bool) throws -> URL {
    let fm = FileManager.default
    let dir = try taxPrepApplicationSupportBase().appendingPathComponent(String(year), isDirectory: true)
    if create {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

private func clearTaxPrepPersistedPacket(for year: Int) throws {
    let fm = FileManager.default
    let dir = try taxPrepPersistedPacketDirectory(for: year, create: false)
    if fm.fileExists(atPath: dir.path) {
        try fm.removeItem(at: dir)
    }
}

// MARK: - Tax optimization persistence (per calendar year)

private let taxOptimizationLastResponseFileName = "lastResponse.raw.txt"

private func taxOptimizationStorageRoot() throws -> URL {
    let fm = FileManager.default
    guard let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        throw NSError(domain: "TaxOpt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Application Support directory."])
    }
    return app
        .appendingPathComponent("TierTap", isDirectory: true)
        .appendingPathComponent("TaxOptimization", isDirectory: true)
}

private func taxOptimizationYearDirectory(for year: Int, create: Bool) throws -> URL {
    let fm = FileManager.default
    let dir = try taxOptimizationStorageRoot().appendingPathComponent(String(year), isDirectory: true)
    if create {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

private func persistTaxOptimizationResponse(year: Int, raw: String) throws {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let dir = try taxOptimizationYearDirectory(for: year, create: true)
    let url = dir.appendingPathComponent(taxOptimizationLastResponseFileName)
    guard let data = trimmed.data(using: .utf8) else { return }
    try data.write(to: url, options: .atomic)
}

private func loadTaxOptimizationResponseIfPresent(year: Int) -> String? {
    guard let url = try? taxOptimizationYearDirectory(for: year, create: false),
          FileManager.default.fileExists(atPath: url.path) else { return nil }
    let fileURL = url.appendingPathComponent(taxOptimizationLastResponseFileName)
    guard FileManager.default.fileExists(atPath: fileURL.path),
          let data = try? Data(contentsOf: fileURL),
          let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !s.isEmpty else {
        return nil
    }
    return s
}

private func taxOptimizationParsedState(from stored: String, language: AppLanguage) -> (TaxOptimizationDisplayModel?, String?) {
    let model = taxOptimizationParseDisplayModel(from: stored, language: language)
        ?? taxOptimizationParseDisplayModel(from: taxPrepDecodeContentOrRaw(stored), language: language)
    if let model {
        return (model, nil)
    }
    let fallback = taxPrepDecodeContentOrRaw(stored).trimmingCharacters(in: .whitespacesAndNewlines)
    if !fallback.isEmpty {
        return (nil, fallback)
    }
    return (nil, nil)
}

// MARK: - Document kinds

private enum TaxPrepDocumentKind: String, Identifiable {
    case annualGamblingTaxSummaryPDF
    case sessionLedgerCSV
    case w2gRegisterCSV
    case irsGamblingDiaryPDF
    case cpaPacketZIP
    case taxExportJSON
    case turboTaxImportCSV

    var id: String { rawValue }

    var displayFileName: String {
        switch self {
        case .annualGamblingTaxSummaryPDF: return "Annual Gambling Tax Summary.pdf"
        case .sessionLedgerCSV: return "Session Ledger.csv"
        case .w2gRegisterCSV: return "W2G Register.csv"
        case .irsGamblingDiaryPDF: return "IRS Gambling Diary.pdf"
        case .cpaPacketZIP: return "CPA Packet.zip"
        case .taxExportJSON: return "Tax Export.json"
        case .turboTaxImportCSV: return "TurboTax Import.csv"
        }
    }

    static func pipeline(includeTurboTax: Bool) -> [TaxPrepDocumentKind] {
        var k: [TaxPrepDocumentKind] = [
            .annualGamblingTaxSummaryPDF,
            .sessionLedgerCSV,
            .w2gRegisterCSV,
            .irsGamblingDiaryPDF,
            .cpaPacketZIP,
            .taxExportJSON
        ]
        if includeTurboTax { k.append(.turboTaxImportCSV) }
        return k
    }
}

private enum TaxPrepRowStatus: Equatable {
    case pending
    case generating
    case ready(URL)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var readyURL: URL? {
        if case .ready(let u) = self { return u }
        return nil
    }
}

private struct TaxPrepArtifactRow: Identifiable {
    let kind: TaxPrepDocumentKind
    var status: TaxPrepRowStatus
    var id: String { kind.rawValue }
}

#if os(iOS)
private final class TaxPrepQuickLookItem: NSObject, QLPreviewItem {
    let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }
    var previewItemURL: URL? { fileURL }
    var previewItemTitle: String? { fileURL.lastPathComponent }
}

private struct TaxPrepQuickLookSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(item: TaxPrepQuickLookItem(fileURL: url))
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let item: TaxPrepQuickLookItem
        init(item: TaxPrepQuickLookItem) { self.item = item }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item
        }
    }
}

private struct TaxPrepDocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onDismiss() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onDismiss() }
    }
}

private enum TaxPrepActiveSheet: Identifiable {
    case quickLook(URL)
    case share(URL)
    case save(URL)
    case saveAll(UUID, [URL])

    var id: String {
        switch self {
        case .quickLook(let u): return "ql-\(u.path)"
        case .share(let u): return "sh-\(u.path)"
        case .save(let u): return "sv-\(u.path)"
        case .saveAll(let token, _): return "svall-\(token.uuidString)"
        }
    }
}

private struct TaxPrepMultiDocumentExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onDismiss() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onDismiss() }
    }
}
#endif

/// TierTap Pro: sequential AI-assisted US gambling tax-prep exports (not certified tax advice).
struct HistoryTaxPrepView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.appLanguage) private var appLanguage

    @State private var isPaywallPresented = false
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var includeTurboTaxImport = false
    @State private var artifactRows: [TaxPrepArtifactRow] = []
    @State private var bundleRootURL: URL?
    @State private var isRunningDocumentBatch = false
    @State private var batchError: String?
    @State private var exportAlertMessage: String?
    @State private var showTaxOptimizationSheet = false
    @State private var taxOptimizationBody: String?
    @State private var taxOptimizationPresentation: TaxOptimizationDisplayModel?
    @State private var taxOptimizationError: String?
    @State private var isLoadingTaxOptimization = false
    @State private var taxPrepDisclaimerExpanded = true
    @State private var taxPrepDisclaimerAutoCollapseTask: Task<Void, Never>?

#if os(iOS)
    @State private var activeSheet: TaxPrepActiveSheet?
#endif

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private var sessionYears: [Int] {
        var years = Set<Int>()
        let cal = Calendar.current
        for s in sessionStore.sessions {
            years.insert(cal.component(.year, from: s.startTime))
            if let end = s.endTime {
                years.insert(cal.component(.year, from: end))
            }
        }
        return years.sorted(by: >)
    }

    private var yearChangeToken: String {
        "\(sessionStore.sessions.count)-\(sessionYears.map(String.init).joined(separator: ","))"
    }

    private var sessionsForSelectedYear: [Session] {
        taxPrepSessions(inCalendarYear: selectedYear, sessions: sessionStore.sessions)
    }

    private var allArtifactRowsReady: Bool {
        !artifactRows.isEmpty && artifactRows.allSatisfy(\.status.isReady)
    }

    private var readyArtifactURLsInOrder: [URL] {
        artifactRows.compactMap(\.status.readyURL)
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    disclaimerBlock

                    if !hasProAccess {
                        nonSubscriberCard
                    } else if sessionStore.sessions.isEmpty {
                        emptySessionsHint
                    } else {
                        controlsCard
                        turboTaxToggle
                        generateButton
                        taxOptimizationButton
                        if let batchError {
                            Text(batchError)
                                .font(.footnote)
                                .foregroundColor(.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !artifactRows.isEmpty {
                            documentListCard
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .localizedNavigationTitle(L10n.tr("Tax Prep", language: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            clampYearIfNeeded()
            refreshPersistedTaxPrepArtifacts()
        }
        .onChange(of: yearChangeToken) { _ in
            clampYearIfNeeded()
            refreshPersistedTaxPrepArtifacts()
        }
        .onChange(of: selectedYear) { _ in
            refreshPersistedTaxPrepArtifacts()
            if !showTaxOptimizationSheet {
                taxOptimizationPresentation = nil
                taxOptimizationBody = nil
                taxOptimizationError = nil
            }
        }
        .adaptiveSheet(isPresented: $isPaywallPresented) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
        .adaptiveSheet(isPresented: $showTaxOptimizationSheet, onDismiss: {
            isLoadingTaxOptimization = false
        }) {
            TaxOptimizationSheetContent(
                year: selectedYear,
                language: appLanguage,
                presentation: $taxOptimizationPresentation,
                bodyFallback: $taxOptimizationBody,
                errorText: $taxOptimizationError,
                isLoading: $isLoadingTaxOptimization,
                isPresented: $showTaxOptimizationSheet,
                onAppearInitialLoad: {
                    Task { await taxOptimizationSheetAppeared() }
                },
                onRegenerate: {
                    Task { await runTaxOptimizationTipsAndPersist() }
                }
            )
            .environmentObject(settingsStore)
        }
#if os(iOS)
        .sheet(item: $activeSheet) { item in
            switch item {
            case .quickLook(let url):
                TaxPrepQuickLookSheet(url: url)
            case .share(let url):
                ShareSheet(items: [url])
            case .save(let url):
                TaxPrepDocumentExportPicker(url: url, onDismiss: { activeSheet = nil })
            case .saveAll(_, let urls):
                TaxPrepMultiDocumentExportPicker(urls: urls, onDismiss: { activeSheet = nil })
            }
        }
#endif
        .alert(L10n.tr("Couldn’t export file", language: appLanguage), isPresented: .init(
            get: { exportAlertMessage != nil },
            set: { if !$0 { exportAlertMessage = nil } }
        )) {
            Button(L10n.tr("OK", language: appLanguage), role: .cancel) { exportAlertMessage = nil }
        } message: {
            if let exportAlertMessage {
                Text(exportAlertMessage)
            }
        }
    }

    private var disclaimerBlock: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                taxPrepDisclaimerExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(L10n.tr("US-only tax assistance", language: appLanguage))
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: taxPrepDisclaimerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.top, 3)
                }
                if taxPrepDisclaimerExpanded {
                    Text(L10n.tr("This tool is for United States personal gambling session recordkeeping and discussion only. It is not legal, tax, or investment advice. TierTap is not a CPA, enrolled agent, or fiduciary. You must validate all figures, classifications, and conclusions with a qualified accounting or tax professional before relying on them for any filing or decision.", language: appLanguage))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            taxPrepDisclaimerAutoCollapseTask?.cancel()
            taxPrepDisclaimerExpanded = true
            taxPrepDisclaimerAutoCollapseTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        taxPrepDisclaimerExpanded = false
                    }
                }
            }
        }
        .onDisappear {
            taxPrepDisclaimerAutoCollapseTask?.cancel()
            taxPrepDisclaimerAutoCollapseTask = nil
        }
    }

    private var nonSubscriberCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Tax Prep is included with TierTap Pro and uses your TierTap AI token allowance.", language: appLanguage))
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
            Button {
                isPaywallPresented = true
            } label: {
                Text(L10n.tr("View TierTap Pro", language: appLanguage))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.9))
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptySessionsHint: some View {
        L10nText("Complete a session to see your history.")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.78))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                L10nText("Tax Year")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.85))
                if sessionYears.isEmpty {
                    Text(verbatim: "—")
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Picker(selection: $selectedYear) {
                        ForEach(sessionYears, id: \.self) { y in
                            Text(verbatim: String(y)).tag(y)
                        }
                    } label: {
                        Text(verbatim: String(selectedYear))
                            .foregroundColor(.white)
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .disabled(isRunningDocumentBatch)
                }
            }

            Text(verbatim: "\(sessionsForSelectedYear.count) sessions include dates in \(selectedYear).")
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var turboTaxToggle: some View {
        Toggle(isOn: $includeTurboTaxImport) {
            Text(L10n.tr("Include TurboTax Import.csv (optional)", language: appLanguage))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
        .tint(.green)
        .disabled(isRunningDocumentBatch)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var generateButton: some View {
        Button {
            Task { await runSequentialTaxPrepPipeline() }
        } label: {
            HStack(spacing: 6) {
                if isRunningDocumentBatch {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "doc.text.fill")
                }
                Text(L10n.tr("Generate Tax Docs with TierTap AI", language: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(Color.green.opacity(0.9))
            .foregroundColor(.black)
            .cornerRadius(12)
        }
        .disabled(!hasProAccess || sessionsForSelectedYear.isEmpty || isRunningDocumentBatch)
    }

    private var taxOptimizationButton: some View {
        Button {
            taxOptimizationError = nil
            showTaxOptimizationSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.max")
                Text(L10n.tr("Generate Tax Help with TierTap AI", language: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.18))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!hasProAccess || sessionsForSelectedYear.isEmpty || isRunningDocumentBatch)
    }

    private var documentListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Tax prep documents", language: appLanguage))
                .font(.headline)
                .foregroundColor(.white)

#if os(iOS)
            if allArtifactRowsReady {
                Button {
                    activeSheet = .saveAll(UUID(), readyArtifactURLsInOrder)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.arrow.down")
                        Text(L10n.tr("Save all to Files", language: appLanguage))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(isRunningDocumentBatch)

                Text(L10n.tr("Pick a folder and save every document from this tax packet.", language: appLanguage))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
#endif

            ForEach(Array(artifactRows.enumerated()), id: \.element.id) { index, row in
                taxPrepDocumentRow(index: index, row: row)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func taxPrepDocumentRow(index: Int, row: TaxPrepArtifactRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.kind.displayFileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                switch row.status {
                case .pending:
                    Text(L10n.tr("Pending", language: appLanguage))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                case .generating:
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(height: 4)
                case .ready:
                    Label(L10n.tr("Ready", language: appLanguage), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.95))
                case .failed(let msg):
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

#if os(iOS)
            Menu {
                Button {
                    if let u = row.status.readyURL { activeSheet = .quickLook(u) }
                } label: {
                    Label(L10n.tr("Open", language: appLanguage), systemImage: "doc.text")
                }
                .disabled(!row.status.isReady)

                Button {
                    if let u = row.status.readyURL { activeSheet = .save(u) }
                } label: {
                    Label(L10n.tr("Save to Files", language: appLanguage), systemImage: "folder")
                }
                .disabled(!row.status.isReady)

                Button {
                    if let u = row.status.readyURL { activeSheet = .share(u) }
                } label: {
                    Label(L10n.tr("Share", language: appLanguage), systemImage: "square.and.arrow.up")
                }
                .disabled(!row.status.isReady)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.white.opacity(row.status.isReady ? 1 : 0.35))
                    .frame(width: 36, height: 36)
            }
            .disabled(!row.status.isReady && row.status != .generating && row.status != .pending)
#endif
        }
        .padding(.vertical, 6)
    }

    private func clampYearIfNeeded() {
        let ys = sessionYears
        guard !ys.isEmpty else { return }
        if !ys.contains(selectedYear) {
            selectedYear = ys[0]
        }
    }

    private func taxPrepFileNonEmpty(at url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }

    /// Reloads rows from Application Support when not generating (e.g. returning to Tax Prep or changing tax year).
    private func refreshPersistedTaxPrepArtifacts() {
        guard hasProAccess else {
            artifactRows = []
            bundleRootURL = nil
            return
        }
        guard !isRunningDocumentBatch else { return }

        let year = selectedYear
        let fm = FileManager.default
        guard let dir = try? taxPrepPersistedPacketDirectory(for: year, create: false),
              fm.fileExists(atPath: dir.path) else {
            artifactRows = []
            bundleRootURL = nil
            return
        }

        let turboURL = dir.appendingPathComponent(TaxPrepDocumentKind.turboTaxImportCSV.displayFileName)
        let turboSaved = taxPrepFileNonEmpty(at: turboURL)
        let useTurboPipeline = includeTurboTaxImport || turboSaved
        let kinds = TaxPrepDocumentKind.pipeline(includeTurboTax: useTurboPipeline)

        var rows: [TaxPrepArtifactRow] = []
        for k in kinds {
            let u = dir.appendingPathComponent(k.displayFileName)
            if taxPrepFileNonEmpty(at: u) {
                rows.append(TaxPrepArtifactRow(kind: k, status: .ready(u)))
            } else {
                rows.append(TaxPrepArtifactRow(kind: k, status: .pending))
            }
        }

        guard rows.contains(where: { $0.status.isReady }) else {
            artifactRows = []
            bundleRootURL = nil
            return
        }

        bundleRootURL = dir
        artifactRows = rows
        if turboSaved {
            includeTurboTaxImport = true
        }
    }

    private func verifyNonEmptyFile(at url: URL, language: AppLanguage) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw NSError(domain: "TaxPrepExport", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Export file was not created.", language: language)])
        }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            try? fm.removeItem(at: url)
            throw NSError(domain: "TaxPrepExport", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Export file was empty.", language: language)])
        }
    }

    private func setArtifactRow(index: Int, status: TaxPrepRowStatus) {
        guard artifactRows.indices.contains(index) else { return }
        var copy = artifactRows
        let kind = copy[index].kind
        copy[index] = TaxPrepArtifactRow(kind: kind, status: status)
        artifactRows = copy
    }

    private func callGeminiRouter(client: SupabaseClient, prompt: String, language: AppLanguage) async throws -> String {
        struct GeminiRequest: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable { let role: String; let parts: [Part] }
            let contents: [Content]
        }
        let routerBody = GeminiProxyBody(
            contents: [GeminiRequest.Content(role: "user", parts: [.init(text: prompt)])],
            language: language
        )
        let response: GeminiRouterAPIResponse = try await GeminiRouterThrottle.shared.executeWithRetries {
            try await client.functions.invoke(
                "gemini-router",
                options: FunctionInvokeOptions(body: routerBody)
            )
        }
        let hasPro = await MainActor.run { subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive }
        await MainActor.run {
            settingsStore.recordAITelemetry(
                invocationTokens: response.telemetryTokenTotal,
                hasProAccess: hasPro
            )
        }
        return response.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func taxOptimizationSheetAppeared() async {
        guard hasProAccess else { return }
        let year = await MainActor.run { selectedYear }
        let lang = await MainActor.run { settingsStore.appLanguage }

        if let stored = loadTaxOptimizationResponseIfPresent(year: year) {
            await MainActor.run {
                let (p, b) = taxOptimizationParsedState(from: stored, language: lang)
                taxOptimizationPresentation = p
                taxOptimizationBody = b
                taxOptimizationError = nil
                isLoadingTaxOptimization = false
            }
            return
        }

        guard SupabaseConfig.isConfigured, supabase != nil else {
            await MainActor.run {
                taxOptimizationError = L10n.tr("Supabase is not configured. Add your project keys to SupabaseKeys.plist.", language: lang)
                taxOptimizationPresentation = nil
                taxOptimizationBody = nil
                isLoadingTaxOptimization = false
            }
            return
        }

        await runTaxOptimizationTipsAndPersist()
    }

    private func runTaxOptimizationTipsAndPersist() async {
        guard hasProAccess else { return }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            await MainActor.run {
                taxOptimizationError = L10n.tr("Supabase is not configured. Add your project keys to SupabaseKeys.plist.", language: appLanguage)
                taxOptimizationBody = nil
                taxOptimizationPresentation = nil
                isLoadingTaxOptimization = false
            }
            return
        }

        let sessions = sessionsForSelectedYear
        guard !sessions.isEmpty else { return }

        await MainActor.run {
            isLoadingTaxOptimization = true
            taxOptimizationError = nil
            taxOptimizationBody = nil
            taxOptimizationPresentation = nil
        }

        let taxYear = await MainActor.run { selectedYear }
        let lang = await MainActor.run { settingsStore.appLanguage }
        let capped = Array(sessions.sorted { $0.startTime > $1.startTime }.prefix(400))
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = capped.map { TaxPrepSessionLine($0, dateFormatter: df) }

        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(lines)
        } catch {
            await MainActor.run {
                taxOptimizationError = error.localizedDescription
                taxOptimizationPresentation = nil
                isLoadingTaxOptimization = false
            }
            return
        }
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            await MainActor.run {
                taxOptimizationError = L10n.tr("Could not encode session data.", language: lang)
                taxOptimizationPresentation = nil
                isLoadingTaxOptimization = false
            }
            return
        }

        let truncatedNote = sessions.count > capped.count
            ? " Note: only the \(capped.count) most recent sessions in the selected year are included for model limits."
            : ""

        let prompt = """
        Adopt the voice of a seasoned **United States CPA** preparing a concise, organized **client-education** memo about gambling-related tax topics. Be warm, direct, and professional—short sentences, confident guidance, no slang, no markdown, no jokes. You are **not** the user’s actual tax advisor; TierTap is software; this is **general educational material only** and **not** individualized tax, legal, or financial advice.

        The attached `sessions` JSON is the user’s TierTap log for **calendar year \(taxYear)** only.\(truncatedNote) Treat numeric fields as **USD in app units** unless the JSON clearly contradicts that.

        **Grounding rules**
        - Every `sessionExample` string must cite **concrete facts** drawn only from the JSON (e.g. `casino`, `game`, `startTime`, `winLoss`, `totalComp`, `hoursPlayed`, `id`, `status`). **Never invent** amounts, dates, or venues.
        - Prefer **different sessions** across examples when the data supports it.
        - If the dataset is thin, say so briefly in `intro` and still deliver useful sections with conservative examples.

        **Output format (critical)**  
        Return **only** one valid JSON object—no markdown fences, no commentary before or after the JSON. Use **exactly** these camelCase keys:

        {
          "intro": "string, 2–4 sentences in first person plural or professional memo voice; include scope + that a licensed CPA/EA must review their full situation.",
          "sections": [
            {
              "sectionTitle": "string, clear heading (e.g. Recordkeeping & substantiation)",
              "tips": [
                {
                  "headline": "string, punchy label",
                  "advice": "string, 2–4 sentences of CPA-style talking points for a planning conversation",
                  "sessionExample": "string or null — one tight illustration quoting patterns from the JSON; null only if impossible"
                }
              ]
            }
          ],
          "closingReminder": "string, 2–3 sentences on next steps with a tax professional"
        }

        Use **4–6 sections**. Each section must contain **2–3 tips**. Each tip must include a non-null `sessionExample` whenever any session field supports it.

        Sessions JSON:
        \(payloadJSON)
        """

        do {
            let text = try await callGeminiRouter(client: client, prompt: prompt, language: lang)
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = taxPrepDecodeContentOrRaw(cleaned)
            let yearForDisk = taxYear
            await MainActor.run {
                let model = taxOptimizationParseDisplayModel(from: normalized, language: lang)
                    ?? taxOptimizationParseDisplayModel(from: cleaned, language: lang)
                if let model {
                    taxOptimizationPresentation = model
                    taxOptimizationBody = nil
                } else if !normalized.isEmpty {
                    taxOptimizationPresentation = nil
                    taxOptimizationBody = normalized
                } else {
                    taxOptimizationPresentation = nil
                    taxOptimizationBody = L10n.tr("No suggestions were returned. Try again.", language: lang)
                }
                isLoadingTaxOptimization = false
            }
            if !normalized.isEmpty {
                try? persistTaxOptimizationResponse(year: yearForDisk, raw: normalized)
            }
        } catch {
            await MainActor.run {
                taxOptimizationError = L10n.tr("Couldn’t load tax optimization tips.", language: lang)
                taxOptimizationPresentation = nil
                isLoadingTaxOptimization = false
            }
        }
    }

    private func runSequentialTaxPrepPipeline() async {
        guard hasProAccess else { return }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            await MainActor.run {
                batchError = L10n.tr("Supabase is not configured. Add your project keys to SupabaseKeys.plist.", language: appLanguage)
            }
            return
        }

        let sessions = sessionsForSelectedYear
        guard !sessions.isEmpty else { return }

        let capped = Array(sessions.sorted { $0.startTime > $1.startTime }.prefix(400))
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = capped.map { TaxPrepSessionLine($0, dateFormatter: df) }
        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(lines)
        } catch {
            await MainActor.run { batchError = error.localizedDescription }
            return
        }
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            await MainActor.run {
                batchError = L10n.tr("Could not encode session data.", language: appLanguage)
            }
            return
        }

        let truncatedNote = sessions.count > capped.count
            ? " Note: only the \(capped.count) most recent sessions in the selected year are included for model limits."
            : ""

        let taxYear = await MainActor.run { selectedYear }
        let includeTurbo = await MainActor.run { includeTurboTaxImport }
        let lang = await MainActor.run { settingsStore.appLanguage }

        let bundle: URL
        do {
            try clearTaxPrepPersistedPacket(for: taxYear)
            bundle = try taxPrepPersistedPacketDirectory(for: taxYear, create: true)
        } catch {
            await MainActor.run { batchError = error.localizedDescription }
            return
        }

        await MainActor.run {
            batchError = nil
            bundleRootURL = bundle
            isRunningDocumentBatch = true
            artifactRows = TaxPrepDocumentKind.pipeline(includeTurboTax: includeTurbo)
                .map { TaxPrepArtifactRow(kind: $0, status: .pending) }
        }

        let kinds = TaxPrepDocumentKind.pipeline(includeTurboTax: includeTurbo)

        for (index, kind) in kinds.enumerated() {
            await MainActor.run { setArtifactRow(index: index, status: .generating) }
            do {
                let url = try await generateOneDocument(
                    kind: kind,
                    bundle: bundle,
                    cappedSessions: capped,
                    payloadJSON: payloadJSON,
                    taxYear: taxYear,
                    truncatedNote: truncatedNote,
                    client: client,
                    language: lang
                )
                try verifyNonEmptyFile(at: url, language: lang)
                await MainActor.run { setArtifactRow(index: index, status: .ready(url)) }
            } catch {
                await MainActor.run { setArtifactRow(index: index, status: .failed(error.localizedDescription)) }
            }
        }

        await MainActor.run { isRunningDocumentBatch = false }
    }

    private func basePromptPrefix(taxYear: Int, truncatedNote: String) -> String {
        """
        You assist with United States personal gambling session logs for **discussion and recordkeeping only**. Not a CPA, EA, or attorney. Output is not certified for IRS filing.\(truncatedNote)
        Calendar tax year: \(taxYear). App: TierTap. Currency values in JSON are app units (treat as USD unless clearly contradicted).

        """
    }

    private func generateOneDocument(
        kind: TaxPrepDocumentKind,
        bundle: URL,
        cappedSessions: [Session],
        payloadJSON: String,
        taxYear: Int,
        truncatedNote: String,
        client: SupabaseClient,
        language: AppLanguage
    ) async throws -> URL {
        let prefix = basePromptPrefix(taxYear: taxYear, truncatedNote: truncatedNote)
        let outURL = bundle.appendingPathComponent(kind.displayFileName)

        switch kind {
        case .annualGamblingTaxSummaryPDF:
            let prompt = prefix + """
            Sessions JSON follows. Produce an **Annual Gambling Tax Summary** as plain UTF-8 text with ALL CAPS section headings, totals, by-casino rollups, and clear limitations. No markdown fences.

            Optionally wrap the entire plain text in JSON as {\"content\":\"...escaped string...\"} — if you use JSON, escape newlines and quotes inside content properly.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            let body = taxPrepDecodeContentOrRaw(raw)
            let pdfTitle = L10n.tr("Annual Gambling Tax Summary (\(taxYear))", language: language)
            guard let pdfData = await MainActor.run { UserGuidePDFExporter.makePDF(text: body, title: pdfTitle) },
                  !pdfData.isEmpty else {
                throw NSError(domain: "TaxPrep", code: 10, userInfo: [NSLocalizedDescriptionKey: L10n.tr("PDF generation failed.", language: language)])
            }
            try pdfData.write(to: outURL, options: .atomic)
            return outURL

        case .sessionLedgerCSV:
            let prompt = prefix + """
            Sessions JSON follows. Return **only** RFC 4180 CSV (header + one row per session). Columns: id,game,casino,start_time,end_time,duration_hours,total_buy_in,cash_out,win_loss,total_comp,status,game_category,session_mood,rewards_program_name,starting_tier_points,ending_tier_points,tier_points_earned,avg_bet_actual,avg_bet_rated,is_live. ISO-8601 timestamps. Or use JSON {\"content\":\"...csv with escaped newlines...\"}.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            var csv = taxPrepDecodeContentOrRaw(raw)
            if csv.split(separator: "\n").count < 2 || !csv.contains(",") {
                csv = TaxPrepCSVExport.build(for: cappedSessions)
            }
            guard let data = csv.data(using: .utf8) else {
                throw NSError(domain: "TaxPrep", code: 11, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Could not encode CSV data.", language: language)])
            }
            try data.write(to: outURL, options: .atomic)
            return outURL

        case .w2gRegisterCSV:
            let prompt = prefix + """
            Sessions JSON follows. Produce a **W2G-style register** as CSV only: helpful columns for tracking possible W-2G events (not official IRS forms). Include header row. Use estimates from session data only. Or JSON {\"content\":\"...\"}.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            var csv = taxPrepDecodeContentOrRaw(raw)
            if csv.split(separator: "\n").count < 2 {
                csv = TaxPrepW2GFallback.csv(for: cappedSessions)
            }
            guard let data = csv.data(using: .utf8) else {
                throw NSError(domain: "TaxPrep", code: 12, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Could not encode CSV data.", language: language)])
            }
            try data.write(to: outURL, options: .atomic)
            return outURL

        case .irsGamblingDiaryPDF:
            let prompt = prefix + """
            Sessions JSON follows. Produce an **IRS-style gambling diary** narrative: dated entries, location, game, amounts, duration, net result, and comps where known. Plain text suitable for PDF. No markdown fences. Optional JSON {\"content\":\"...\"}.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            let body = taxPrepDecodeContentOrRaw(raw)
            let pdfTitle = L10n.tr("IRS Gambling Diary (\(taxYear))", language: language)
            guard let pdfData = await MainActor.run { UserGuidePDFExporter.makePDF(text: body, title: pdfTitle) },
                  !pdfData.isEmpty else {
                throw NSError(domain: "TaxPrep", code: 13, userInfo: [NSLocalizedDescriptionKey: L10n.tr("PDF generation failed.", language: language)])
            }
            try pdfData.write(to: outURL, options: .atomic)
            return outURL

        case .cpaPacketZIP:
            let readmePrompt = prefix + """
            Summarize how a CPA should use the attached TierTap exports (annual summary PDF, session ledger CSV, W2G register CSV, IRS diary PDF) for \(taxYear). Plain text README only (no markdown). Optional JSON {\"content\":\"...\"}.
            """
            let readmeRaw = try await callGeminiRouter(client: client, prompt: readmePrompt, language: language)
            let readme = taxPrepDecodeContentOrRaw(readmeRaw)
            let readmeData = readme.data(using: .utf8) ?? Data()

            let four: [TaxPrepDocumentKind] = [
                .annualGamblingTaxSummaryPDF,
                .sessionLedgerCSV,
                .w2gRegisterCSV,
                .irsGamblingDiaryPDF
            ]
            let rowsNow = await MainActor.run { artifactRows }
            var entries: [(fileName: String, data: Data)] = [("CPA_README.txt", readmeData)]
            for fk in four {
                guard let row = rowsNow.first(where: { $0.kind == fk }),
                      case .ready(let u) = row.status else {
                    throw NSError(domain: "TaxPrep", code: 14, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Earlier exports are not ready; cannot build CPA Packet.", language: language)])
                }
                let data = try Data(contentsOf: u)
                entries.append((fk.displayFileName, data))
            }
            try TaxPrepZipArchive.makeZip(entries: entries, to: outURL)
            return outURL

        case .taxExportJSON:
            let prompt = prefix + """
            Sessions JSON follows. Return **only** a single JSON object suitable for archival export. Include keys: taxYear (number), disclaimer (string), sessions (array echoing or summarizing input), aiNotes (string, may be empty). Must be valid JSON. No markdown fences.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            let slice = taxPrepExtractJSONObject(from: raw)
            let dataToWrite: Data
            if let d = slice.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: d)) != nil {
                dataToWrite = d
            } else {
                let fb = TaxExportFallback(
                    taxYear: taxYear,
                    disclaimer: L10n.tr("US-only TierTap export. Not certified tax advice.", language: language),
                    sessions: cappedSessions.map { TaxPrepSessionLine($0, dateFormatter: dfISO()) }
                )
                dataToWrite = try JSONEncoder().encode(fb)
            }
            try dataToWrite.write(to: outURL, options: .atomic)
            return outURL

        case .turboTaxImportCSV:
            let prompt = prefix + """
            Sessions JSON follows. Produce a **TurboTax-friendly import CSV** (generic columns: date, description, amount, category). One row per session net. RFC 4180. Or JSON {\"content\":\"...\"}.

            Sessions JSON:
            \(payloadJSON)
            """
            let raw = try await callGeminiRouter(client: client, prompt: prompt, language: language)
            var csv = taxPrepDecodeContentOrRaw(raw)
            if csv.split(separator: "\n").count < 2 {
                csv = TaxPrepTurboTaxFallback.csv(for: cappedSessions)
            }
            guard let data = csv.data(using: .utf8) else {
                throw NSError(domain: "TaxPrep", code: 15, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Could not encode CSV data.", language: language)])
            }
            try data.write(to: outURL, options: .atomic)
            return outURL
        }
    }

    private func dfISO() -> ISO8601DateFormatter {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return df
    }
}

private struct TaxOptimizationSheetContent: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let year: Int
    let language: AppLanguage
    @Binding var presentation: TaxOptimizationDisplayModel?
    @Binding var bodyFallback: String?
    @Binding var errorText: String?
    @Binding var isLoading: Bool
    @Binding var isPresented: Bool
    let onAppearInitialLoad: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L10n.tr("TierTap AI is summarizing ideas that people often discuss with a tax professional. This is not tax advice.", language: language))
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.22))
                            )

                        HStack(spacing: 6) {
                            Text(L10n.tr("Tax Year", language: language))
                            Text(verbatim: String(year))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.78))

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundColor(.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.red.opacity(0.18))
                                )
                        }

                        if let p = presentation {
                            if let intro = p.intro {
                                TaxOptimizationIntroCapsule(text: intro)
                            }
                            ForEach(p.sections) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    TaxOptimizationSectionHeader(title: section.title)
                                    ForEach(section.tips) { tip in
                                        TaxOptimizationTipBubble(tip: tip, language: language)
                                    }
                                }
                            }
                            if let closing = p.closingReminder {
                                TaxOptimizationClosingCard(text: closing)
                            }
                        } else if let body = bodyFallback, !body.isEmpty {
                            TaxOptimizationIntroCapsule(text: body)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(L10n.tr("Tax Optimization", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onRegenerate()
                    } label: {
                        Text(L10n.tr("Regenerate", language: language))
                            .font(.subheadline.weight(.semibold))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", language: language)) {
                        isPresented = false
                    }
                    .foregroundColor(.primary)

                }
            }
            .onAppear(perform: onAppearInitialLoad)
        }
    }
}

private struct TaxOptimizationIntroCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.92))
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

private struct TaxOptimizationSectionHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.green.opacity(0.9))
                .frame(width: 4, height: 22)
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

private struct TaxOptimizationTipBubble: View {
    let tip: TaxOptimizationDisplayModel.Tip
    let language: AppLanguage
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                expanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(tip.headline)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.72))
                }
                if expanded {
                    Text(tip.advice)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let ex = tip.sessionExample, !ex.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.caption.weight(.semibold))
                                Text(L10n.tr("From your records", language: language))
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.green.opacity(0.95))
                            Text(ex)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TaxOptimizationClosingCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundColor(.white.opacity(0.94))
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(0.42), lineWidth: 1)
            )
    }
}
