import SwiftUI
import Supabase
#if canImport(UIKit)
import UIKit
#endif

enum LoyaltyCalculatorKind: String, CaseIterable, Identifiable {
    case blackjackTheo
    case baccaratTheo
    case rouletteTheo
    case crapsTheo
    case slotTheo
    case casinoADT
    case casinoComp
    case casinoTier

    var id: String { rawValue }

    /// Free users can open these without Pro; the rest are blurred and open the paywall.
    var isFree: Bool {
        switch self {
        case .blackjackTheo, .baccaratTheo, .slotTheo: return true
        case .rouletteTheo, .crapsTheo, .casinoADT, .casinoComp, .casinoTier: return false
        }
    }

    var title: String {
        switch self {
        case .blackjackTheo: return "Blackjack Theo Calculator"
        case .baccaratTheo: return "Baccarat Theo Calculator"
        case .rouletteTheo: return "Roulette Theo Calculator"
        case .crapsTheo: return "Craps Theo Calculator"
        case .slotTheo: return "Slot Theo Calculator"
        case .casinoADT: return "Casino ADT Calculator"
        case .casinoComp: return "Casino Comp Calculator"
        case .casinoTier: return "Casino Tier Calculator"
        }
    }

    var subtitle: String {
        switch self {
        case .blackjackTheo: return "Estimate theoretical loss from BJ play"
        case .baccaratTheo: return "Banker, Player, or Tie house edge"
        case .rouletteTheo: return "American, European, or custom edge"
        case .crapsTheo: return "Pass / Odds blended house edge"
        case .slotTheo: return "Coin-in × hold or bet × spin pace"
        case .casinoADT: return "Average Daily Theo from play or trip"
        case .casinoComp: return "Rematch comps from theoretical loss"
        case .casinoTier: return "Tier points from theo or coin-in"
        }
    }

    var systemImage: String {
        switch self {
        case .blackjackTheo: return "suit.spade.fill"
        case .baccaratTheo: return "suit.club.fill"
        case .rouletteTheo: return "target"
        case .crapsTheo: return "dice.fill"
        case .slotTheo: return "square.grid.3x3.fill"
        case .casinoADT: return "calendar"
        case .casinoComp: return "gift.fill"
        case .casinoTier: return "chart.line.uptrend.xyaxis"
        }
    }

    var shortGameLabel: String {
        switch self {
        case .blackjackTheo: return "blackjack"
        case .baccaratTheo: return "baccarat"
        case .rouletteTheo: return "roulette"
        case .crapsTheo: return "craps"
        case .slotTheo: return "slots"
        case .casinoADT: return "average daily theo (ADT)"
        case .casinoComp: return "casino comps"
        case .casinoTier: return "tier points"
        }
    }
}

/// Modal hub for host-style loyalty calculators (theo, ADT, comps, tiers).
struct LoyaltyCalculatorView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var isPaywallPresented = false

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        L10nText("Estimate theoretical loss, ADT, comps, and tier points. Edges are approximations and vary by rules and casino.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)

                        if !hasProAccess {
                            L10nText("Free includes Blackjack, Baccarat, and Slots. Unlock the rest with TierTap Pro.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(LoyaltyCalculatorKind.allCases) { kind in
                            let locked = !kind.isFree && !hasProAccess
                            if locked {
                                Button {
                                    isPaywallPresented = true
                                } label: {
                                    calculatorRow(kind, isLocked: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(kind.title). Locked. Unlock with TierTap Pro.")
                            } else {
                                NavigationLink {
                                    LoyaltyCalculatorDetailView(kind: kind)
                                        .environmentObject(settingsStore)
                                        .environmentObject(subscriptionStore)
                                        .environmentObject(authStore)
                                } label: {
                                    calculatorRow(kind, isLocked: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .localizedNavigationTitle("Loyalty Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
        .adaptiveSheet(isPresented: $isPaywallPresented) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
    }

    private func calculatorRow(_ kind: LoyaltyCalculatorKind, isLocked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundColor(isLocked ? .white.opacity(0.45) : .green)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .blur(radius: isLocked ? 2.5 : 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    if isLocked {
                        Text("PRO")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .blur(radius: isLocked ? 4 : 0)
            }

            Spacer(minLength: 0)

            Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(isLocked ? 0.7 : 0.45))
        }
        .padding(14)
        .background(Color.white.opacity(isLocked ? 0.08 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isLocked {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Detail router

private struct LoyaltyCalculatorDetailView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    let kind: LoyaltyCalculatorKind

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            Group {
                switch kind {
                case .blackjackTheo:
                    TableTheoCalculatorForm(
                        kind: kind,
                        title: "Blackjack",
                        averageBetHint: "Average bet",
                        paceLabel: "Hands / hour",
                        defaultPace: "70",
                        presetTitles: BlackjackEdgePreset.allCases.map(\.title),
                        presetEdges: BlackjackEdgePreset.allCases.map(\.edgePercent),
                        defaultPresetIndex: 0
                    )
                case .baccaratTheo:
                    TableTheoCalculatorForm(
                        kind: kind,
                        title: "Baccarat",
                        averageBetHint: "Average bet",
                        paceLabel: "Hands / hour",
                        defaultPace: "70",
                        presetTitles: BaccaratBetPreset.allCases.map(\.title),
                        presetEdges: BaccaratBetPreset.allCases.map(\.edgePercent),
                        defaultPresetIndex: 0
                    )
                case .rouletteTheo:
                    TableTheoCalculatorForm(
                        kind: kind,
                        title: "Roulette",
                        averageBetHint: "Average bet",
                        paceLabel: "Spins / hour",
                        defaultPace: "35",
                        presetTitles: RouletteWheelPreset.allCases.map(\.title),
                        presetEdges: RouletteWheelPreset.allCases.map(\.edgePercent),
                        defaultPresetIndex: 0
                    )
                case .crapsTheo:
                    TableTheoCalculatorForm(
                        kind: kind,
                        title: "Craps",
                        averageBetHint: "Avg bet / decision",
                        paceLabel: "Decisions / hour",
                        defaultPace: "30",
                        presetTitles: CrapsBetPreset.allCases.map(\.title),
                        presetEdges: CrapsBetPreset.allCases.map(\.edgePercent),
                        defaultPresetIndex: 0
                    )
                case .slotTheo:
                    SlotTheoCalculatorForm(kind: kind)
                case .casinoADT:
                    CasinoADTCalculatorForm(kind: kind)
                case .casinoComp:
                    CasinoCompCalculatorForm(kind: kind)
                case .casinoTier:
                    CasinoTierCalculatorForm(kind: kind)
                }
            }
        }
        .localizedNavigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - TierTap AI Insight

/// Session-scoped cache so reopening the insights drawer with unchanged inputs reuses the last Gemini text.
@MainActor
private final class LoyaltyCalculatorInsightCache: ObservableObject {
    private var textBySummary: [String: String] = [:]

    func text(for summary: String) -> String? {
        textBySummary[summary]
    }

    func store(_ text: String, for summary: String) {
        textBySummary[summary] = text
        objectWillChange.send()
    }

    func clear(for summary: String) {
        textBySummary.removeValue(forKey: summary)
        objectWillChange.send()
    }
}

/// Short gemini-router insight attached under calculator results (auth / Pro / token gates).
private struct LoyaltyCalculatorInsightSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject private var insightCache: LoyaltyCalculatorInsightCache

    let kind: LoyaltyCalculatorKind
    /// Stable summary of the current numeric result; nil hides the insight UI.
    let resultSummary: String?

    @State private var isPaywallPresented = false
    @State private var isLoading = false
    @State private var insightText: String?
    @State private var errorMessage: String?
    @State private var lastFetchedSummary: String?
    @State private var fetchTask: Task<Void, Never>?

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    /// Free users share the global daily Gemini cap; Pro uses the token-backed path.
    private var freeDailyAILimitReached: Bool {
        guard !hasProAccess else { return false }
        return !settingsStore.canInvokeTierTapAIFeatures(hasProAccess: false)
            && authStore.isSignedIn
    }

    var body: some View {
        Group {
            if let summary = resultSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.green)
                        Text("TierTap AI Insight")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }

                    if settingsStore.requiresTierTapAIFeaturePaywall(
                        isSignedIn: authStore.isSignedIn,
                        hasProAccess: hasProAccess
                    ) || freeDailyAILimitReached {
                        // Still show a previously generated insight for this exact input set.
                        if let cached = insightCache.text(for: summary) ?? insightText {
                            Text(cached)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            isPaywallPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                L10nText(authStore.isSignedIn
                                         ? (freeDailyAILimitReached
                                            ? "Daily AI limit reached — Upgrade"
                                            : "Unlock TierTap AI Insights")
                                         : "Sign in for TierTap AI Insights")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if freeDailyAILimitReached {
                            Text("Free TierTap AI Insights are limited to \(settingsStore.maxAICallsPerDay) calls per day (shared across the app). Upgrade to Pro for more.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.orange.opacity(0.95))
                        Button {
                            lastFetchedSummary = nil
                            insightCache.clear(for: summary)
                            scheduleFetch(for: summary)
                        } label: {
                            L10nText("Try again")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.green)
                        }
                    } else if let insightText {
                        Text(insightText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !isLoading {
                        L10nText("Generating a short host-style take…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: summary) { newValue in
                    scheduleFetch(for: newValue)
                }
                .onAppear {
                    scheduleFetch(for: summary)
                }
                .onDisappear {
                    fetchTask?.cancel()
                }
            }
        }
        .adaptiveSheet(isPresented: $isPaywallPresented) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
    }

    private func scheduleFetch(for summary: String) {
        fetchTask?.cancel()

        // Reuse cached insight when inputs (result summary) have not changed.
        if let cached = insightCache.text(for: summary) {
            insightText = cached
            lastFetchedSummary = summary
            errorMessage = nil
            isLoading = false
            return
        }

        // Free users: after the shared daily Gemini cap (default 5), pop the subscribe sheet.
        if presentSubscribeIfAIBlocked() {
            return
        }

        if summary == lastFetchedSummary, insightText != nil { return }

        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await fetchInsight(summary: summary)
        }
    }

    /// Returns true when Gemini should not run (and the paywall may have been presented).
    @discardableResult
    private func presentSubscribeIfAIBlocked() -> Bool {
        // Free users share the global daily Gemini cap (default 5). Over limit → subscribe sheet.
        if freeDailyAILimitReached {
            insightText = nil
            isLoading = false
            errorMessage = "You have reached the daily limit of \(settingsStore.maxAICallsPerDay) AI calls on the free version of TierTap. Upgrade to the PRO version for more TierTap AI Insights."
            isPaywallPresented = true
            return true
        }

        if settingsStore.requiresTierTapAIFeaturePaywall(
            isSignedIn: authStore.isSignedIn,
            hasProAccess: hasProAccess
        ) {
            insightText = nil
            errorMessage = nil
            isLoading = false
            // Pro token exhaustion also routes to the subscribe / token paywall.
            if hasProAccess {
                isPaywallPresented = true
            }
            return true
        }
        return false
    }

    @MainActor
    private func fetchInsight(summary: String) async {
        guard SupabaseConfig.isConfigured, let client = supabase else {
            errorMessage = L10n.tr("Supabase is not configured.", language: settingsStore.appLanguage)
            return
        }

        if presentSubscribeIfAIBlocked() {
            return
        }

        isLoading = true
        errorMessage = nil

        let prompt = """
        You are a concise casino host / player-development coach inside TierTap.
        The player just ran the \(kind.shortGameLabel) loyalty calculator with this result:
        \(summary)

        Write 2 short sentences (max ~45 words total) that help them interpret host value: theo, comps, tier pace, or session pacing — whichever fits best.
        Be practical and specific to the numbers. No bullet lists, no markdown, no disclaimers about gambling addiction, no asking for more data.
        """

        struct GeminiRequest: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable {
                let role: String
                let parts: [Part]
            }
            let contents: [Content]
        }

        let routerBody = GeminiProxyBody(
            contents: [
                GeminiRequest.Content(role: "user", parts: [.init(text: prompt)])
            ],
            language: settingsStore.appLanguage
        )

        do {
            let response: GeminiRouterAPIResponse = try await GeminiRouterThrottle.shared.executeWithRetries {
                try await client.functions.invoke(
                    "gemini-router",
                    options: FunctionInvokeOptions(body: routerBody)
                )
            }
            // Count toward the shared free daily Gemini cap only after a successful call.
            if !hasProAccess {
                settingsStore.registerAICall()
            }
            settingsStore.recordAITelemetry(
                invocationTokens: response.telemetryTokenTotal,
                hasProAccess: hasProAccess
            )
            let text = response.candidates?
                .first?
                .content?
                .parts?
                .compactMap { $0.text }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            insightText = (text?.isEmpty == false)
                ? text
                : L10n.tr("No text response from Gemini.", language: settingsStore.appLanguage)
            if let insightText {
                insightCache.store(insightText, for: summary)
            }
            lastFetchedSummary = summary
            isLoading = false
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Shared form pieces

private struct CalculatorTheoBubble: View {
    let title: String
    let value: String
    /// Negative theo / +EV styled as a win bubble; positive theo as a loss.
    let isPositiveEV: Bool
    var detail: String? = nil
    /// When nil, uses Theo win (+EV) / Theo loss. Pass a custom caption for comps/tiers.
    var outcomeCaption: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(isPositiveEV ? .green : Color.orange)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
            Text(outcomeCaption ?? (isPositiveEV ? "Theo win (+EV)" : "Theo loss"))
                .font(.caption2.weight(.bold))
                .foregroundColor(isPositiveEV ? .green.opacity(0.9) : Color.orange.opacity(0.9))
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isPositiveEV ? Color.green : Color.orange).opacity(0.45), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Cooldown between TierTap AI Insights button taps (seconds).
private let loyaltyCalculatorInsightsCooldownSeconds = 3

/// Scrollable inputs + bottom CTA that presents theo bubbles and TierTap AI Insight.
private struct CalculatorFormShell<FormContent: View, InsightsContent: View>: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let insightsReady: Bool
    @ViewBuilder let formContent: () -> FormContent
    @ViewBuilder let insightsContent: () -> InsightsContent

    @State private var showInsights = false
    @State private var isCoolingDown = false
    @State private var cooldownSecondsRemaining = 0
    @State private var cooldownTask: Task<Void, Never>?
    @StateObject private var insightCache = LoyaltyCalculatorInsightCache()

    private var canOpenInsights: Bool {
        insightsReady && !isCoolingDown
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                formContent()
                    .padding()
                    .padding(.bottom, 12)
            }

            VStack(spacing: 8) {
                Divider().background(Color.white.opacity(0.2))
                Button {
                    guard canOpenInsights else { return }
                    showInsights = true
                    beginInsightsCooldown()
                } label: {
                    HStack(spacing: 10) {
                        if isCoolingDown {
                            ProgressView()
                                .tint(canOpenInsights ? .black : .white.opacity(0.7))
                            Text(cooldownSecondsRemaining > 0
                                  ? "Please wait… \(cooldownSecondsRemaining)s"
                                  : "Please wait…")
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text("TierTap AI Insights")
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.headline)
                    .foregroundColor(canOpenInsights ? .black : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canOpenInsights ? Color.green : Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .animation(.easeInOut(duration: 0.15), value: isCoolingDown)
                }
                .buttonStyle(.plain)
                .disabled(!canOpenInsights)
                .accessibilityLabel(isCoolingDown ? "Please wait" : "TierTap AI Insights")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Color.black.opacity(0.25))
        }
        .onDisappear {
            cooldownTask?.cancel()
            cooldownTask = nil
        }
        .sheet(isPresented: $showInsights) {
            NavigationStack {
                ZStack {
                    settingsStore.primaryGradient.ignoresSafeArea()
                    ScrollView {
                        insightsContent()
                            .padding()
                            .padding(.bottom, 28)
                    }
                }
                .localizedNavigationTitle("TierTap AI Insights")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showInsights = false }
                            .foregroundColor(.green)
                    }
                }
            }
            .environmentObject(insightCache)
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.visible)
        }
    }

    private func beginInsightsCooldown() {
        cooldownTask?.cancel()
        isCoolingDown = true
        cooldownSecondsRemaining = loyaltyCalculatorInsightsCooldownSeconds
        cooldownTask = Task { @MainActor in
            for remaining in stride(from: loyaltyCalculatorInsightsCooldownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                cooldownSecondsRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            cooldownSecondsRemaining = 0
            isCoolingDown = false
            cooldownTask = nil
        }
    }
}

private struct CalculatorFieldRow: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let label: String
    @Binding var text: String
    var suffix: String? = nil
    @State private var showDialPad = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 118, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("0", text: $text)
                    .textFieldStyle(DarkTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let suffix {
                    Text(suffix)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }
                DialPadLaunchButton { showDialPad = true }
            }
        }
        .sheet(isPresented: $showDialPad) {
            NumericDialPadSheet(value: $text, navigationTitle: label)
                .environmentObject(settingsStore)
        }
    }
}

private func parseDouble(_ text: String) -> Double? {
    let cleaned = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: "")
    guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
    return value
}

private func formatMoney(_ value: Double, symbol: String) -> String {
    let absValue = abs(value)
    let formatted = absValue.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(symbol)\(formatted)"
}

private func formatPoints(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).grouping(.automatic))
}

private func theoOutcomeDetail(paceLabel: String, beneficiary: LoyaltyEdgeBeneficiary) -> String {
    let edgeWord = beneficiary == .playerAdvantage ? "player edge" : "house edge"
    return "Theo = avg bet × \(paceLabel.lowercased()) × hours × \(edgeWord)"
}

private func formatSignedEdgePercent(_ edge: Double) -> String {
    let formatted = abs(edge).formatted(.number.precision(.fractionLength(0...2)))
    if edge < 0 { return "−\(formatted)% player edge" }
    if edge > 0 { return "+\(formatted)% house edge" }
    return "0% edge"
}

private struct EdgeBeneficiaryPicker: View {
    @Binding var beneficiary: LoyaltyEdgeBeneficiary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edge favors")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            Picker("Edge favors", selection: $beneficiary) {
                ForEach(LoyaltyEdgeBeneficiary.allCases) { option in
                    Text(option.shortTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)
            if beneficiary == .playerAdvantage {
                Text("Player edge models advantage / +EV play. Theo becomes an expected win.")
                    .font(.caption2)
                    .foregroundColor(.green.opacity(0.85))
            }
        }
    }
}

// MARK: - Table game theo form

private struct TableTheoCalculatorForm: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore

    let kind: LoyaltyCalculatorKind
    let title: String
    let averageBetHint: String
    let paceLabel: String
    let defaultPace: String
    let presetTitles: [String]
    let presetEdges: [Double?]
    let defaultPresetIndex: Int

    @State private var averageBet = ""
    @State private var pace = ""
    @State private var hours = ""
    @State private var customEdge = ""
    @State private var presetIndex = 0
    @State private var edgeBeneficiary: LoyaltyEdgeBeneficiary = .house

    var body: some View {
        CalculatorFormShell(insightsReady: computedTheo != nil) {
            VStack(alignment: .leading, spacing: 14) {
                edgePicker
                EdgeBeneficiaryPicker(beneficiary: $edgeBeneficiary)

                CalculatorFieldRow(
                    label: averageBetHint,
                    text: $averageBet,
                    suffix: settingsStore.currencySymbol
                )
                CalculatorFieldRow(label: paceLabel, text: $pace)
                CalculatorFieldRow(label: "Hours played", text: $hours)

                if isCustomEdge {
                    CalculatorFieldRow(
                        label: "Edge magnitude",
                        text: $customEdge,
                        suffix: "%"
                    )
                }

                if computedTheo == nil {
                    hintCard("Fill average bet, pace, hours, and an edge — then open TierTap AI Insights.")
                }

                disclaimer
            }
            .onAppear {
                if pace.isEmpty { pace = defaultPace }
                presetIndex = min(defaultPresetIndex, max(0, presetTitles.count - 1))
                if customEdge.isEmpty { customEdge = "1" }
            }
        } insightsContent: {
            if let theo = computedTheo, let edge = resolvedEdge {
                VStack(alignment: .leading, spacing: 16) {
                    CalculatorTheoBubble(
                        title: title,
                        value: formatMoney(abs(theo), symbol: settingsStore.currencySymbol),
                        isPositiveEV: theo < 0,
                        detail: "\(theoOutcomeDetail(paceLabel: paceLabel, beneficiary: edgeBeneficiary)) · \(formatSignedEdgePercent(edge))"
                    )
                    LoyaltyCalculatorInsightSection(
                        kind: kind,
                        resultSummary: """
                        \(title) \(theo < 0 ? "theoretical win (+EV)" : "theo") \(formatMoney(abs(theo), symbol: settingsStore.currencySymbol)) from avg bet \(averageBet), \(paceLabel.lowercased()) \(pace), hours \(hours), \(formatSignedEdgePercent(edge)).
                        """
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
                }
            }
        }
        .environmentObject(settingsStore)
    }

    private var isCustomEdge: Bool {
        guard let maybeEdge = presetEdges[safe: presetIndex] else { return true }
        return maybeEdge == nil
    }

    private var magnitudeEdge: Double? {
        if let maybeEdge = presetEdges[safe: presetIndex], let preset = maybeEdge {
            return abs(preset)
        }
        return parseDouble(customEdge).map(abs)
    }

    private var resolvedEdge: Double? {
        guard let magnitude = magnitudeEdge else { return nil }
        return edgeBeneficiary.signedPercent(magnitude: magnitude)
    }

    private var computedTheo: Double? {
        guard
            let bet = parseDouble(averageBet),
            let paceValue = parseDouble(pace),
            let hoursValue = parseDouble(hours),
            let edge = resolvedEdge
        else { return nil }
        return LoyaltyCalculatorMath.theo(
            averageBet: bet,
            decisionsPerHour: paceValue,
            hours: hoursValue,
            houseEdgePercent: edge
        )
    }

    private var edgePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edge preset")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            Picker("Edge preset", selection: $presetIndex) {
                ForEach(presetTitles.indices, id: \.self) { index in
                    Text(presetTitles[index]).tag(index)
                }
            }
            .pickerStyle(.menu)
            .tint(.green)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: presetIndex) { newValue in
                let selectingCustom = (presetEdges[safe: newValue] ?? nil) == nil
                guard selectingCustom else { return }
                if let value = parseDouble(customEdge) {
                    customEdge = String(max(0, Int(value.rounded())))
                } else {
                    customEdge = "1"
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("Edges are approximate. Flip to Player edge (+EV) for advantage situations. Rating formulas and speed of play vary by casino.")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.55))
    }
}

// MARK: - Slots

private struct SlotTheoCalculatorForm: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore

    let kind: LoyaltyCalculatorKind

    private enum Mode: String, CaseIterable, Identifiable {
        case coinIn
        case pace
        var id: String { rawValue }
        var title: String {
            switch self {
            case .coinIn: return "Coin-in × hold %"
            case .pace: return "Bet × spins × hours"
            }
        }
    }

    @State private var mode: Mode = .coinIn
    @State private var coinIn = ""
    @State private var averageBet = ""
    @State private var spinsPerHour = "600"
    @State private var hours = ""
    @State private var holdPercent = "8"
    @State private var edgeBeneficiary: LoyaltyEdgeBeneficiary = .house

    var body: some View {
        CalculatorFormShell(insightsReady: computed != nil) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                EdgeBeneficiaryPicker(beneficiary: $edgeBeneficiary)
                CalculatorFieldRow(
                    label: "Edge magnitude",
                    text: $holdPercent,
                    suffix: "%"
                )

                switch mode {
                case .coinIn:
                    CalculatorFieldRow(
                        label: "Total coin-in",
                        text: $coinIn,
                        suffix: settingsStore.currencySymbol
                    )
                case .pace:
                    CalculatorFieldRow(
                        label: "Average bet",
                        text: $averageBet,
                        suffix: settingsStore.currencySymbol
                    )
                    CalculatorFieldRow(label: "Spins / hour", text: $spinsPerHour)
                    CalculatorFieldRow(label: "Hours played", text: $hours)
                }

                if computed == nil {
                    hintCard("Fill hold and coin-in or pace — then open TierTap AI Insights.")
                }

                Text("Slot hold varies widely by machine and jurisdiction. Use Player edge (+EV) for promo / advantage situations.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
        } insightsContent: {
            if let result = computed {
                VStack(alignment: .leading, spacing: 16) {
                    CalculatorTheoBubble(
                        title: "Slots",
                        value: formatMoney(abs(result.theo), symbol: settingsStore.currencySymbol),
                        isPositiveEV: result.theo < 0,
                        detail: result.detail
                    )
                    LoyaltyCalculatorInsightSection(
                        kind: kind,
                        resultSummary: result.insightSummary
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
                }
            }
        }
        .environmentObject(settingsStore)
    }

    private var signedHold: Double? {
        guard let magnitude = parseDouble(holdPercent) else { return nil }
        return edgeBeneficiary.signedPercent(magnitude: magnitude)
    }

    private var computed: (theo: Double, detail: String, insightSummary: String)? {
        guard let hold = signedHold else { return nil }
        switch mode {
        case .coinIn:
            guard let coin = parseDouble(coinIn),
                  let theo = LoyaltyCalculatorMath.slotTheoFromCoinIn(coinIn: coin, holdPercent: hold)
            else { return nil }
            return (
                theo,
                "Theo = coin-in × \(edgeBeneficiary == .playerAdvantage ? "player edge" : "hold") · \(formatSignedEdgePercent(hold))",
                "Slots \(theo < 0 ? "theoretical win (+EV)" : "theo") \(formatMoney(abs(theo), symbol: settingsStore.currencySymbol)) from coin-in \(formatMoney(coin, symbol: settingsStore.currencySymbol)) at \(formatSignedEdgePercent(hold))."
            )
        case .pace:
            guard let bet = parseDouble(averageBet),
                  let spins = parseDouble(spinsPerHour),
                  let hrs = parseDouble(hours),
                  let theo = LoyaltyCalculatorMath.slotTheoFromPace(
                    averageBet: bet,
                    spinsPerHour: spins,
                    hours: hrs,
                    holdPercent: hold
                  )
            else { return nil }
            let coin = bet * spins * hrs
            return (
                theo,
                "Coin-in \(formatMoney(coin, symbol: settingsStore.currencySymbol)) × edge · \(formatSignedEdgePercent(hold))",
                "Slots \(theo < 0 ? "theoretical win (+EV)" : "theo") \(formatMoney(abs(theo), symbol: settingsStore.currencySymbol)) from avg bet \(formatMoney(bet, symbol: settingsStore.currencySymbol)), \(Int(spins)) spins/hr, \(hrs) hours, \(formatSignedEdgePercent(hold)) (coin-in \(formatMoney(coin, symbol: settingsStore.currencySymbol)))."
            )
        }
    }
}

// MARK: - ADT

private struct CasinoADTCalculatorForm: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore

    let kind: LoyaltyCalculatorKind

    private enum Mode: String, CaseIterable, Identifiable {
        case fromPlay
        case fromTotal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fromPlay: return "From play metrics"
            case .fromTotal: return "Total theo ÷ days"
            }
        }
    }

    @State private var mode: Mode = .fromPlay
    @State private var averageBet = ""
    @State private var decisionsPerHour = "60"
    @State private var hoursPerDay = ""
    @State private var houseEdge = "1"
    @State private var days = "1"
    @State private var totalTheo = ""
    @State private var edgeBeneficiary: LoyaltyEdgeBeneficiary = .house

    var body: some View {
        CalculatorFormShell(insightsReady: computed != nil) {
            VStack(alignment: .leading, spacing: 14) {
                L10nText("ADT = Average Daily Theo — theoretical daily result (loss or +EV win).")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .fromPlay:
                    CalculatorFieldRow(
                        label: "Average bet",
                        text: $averageBet,
                        suffix: settingsStore.currencySymbol
                    )
                    CalculatorFieldRow(label: "Decisions / hour", text: $decisionsPerHour)
                    CalculatorFieldRow(label: "Hours per day", text: $hoursPerDay)
                    EdgeBeneficiaryPicker(beneficiary: $edgeBeneficiary)
                    CalculatorFieldRow(
                        label: "Edge magnitude",
                        text: $houseEdge,
                        suffix: "%"
                    )
                    CalculatorFieldRow(label: "Days in trip", text: $days)
                case .fromTotal:
                    CalculatorFieldRow(
                        label: "Total trip theo",
                        text: $totalTheo,
                        suffix: settingsStore.currencySymbol
                    )
                    CalculatorFieldRow(label: "Days played", text: $days)
                }

                if computed == nil {
                    hintCard("Fill the fields above — then open TierTap AI Insights.")
                }
            }
        } insightsContent: {
            if let result = computed {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CalculatorTheoBubble(
                            title: "ADT",
                            value: formatMoney(abs(result.adt), symbol: settingsStore.currencySymbol),
                            isPositiveEV: result.adt < 0,
                            detail: result.detail
                        )
                        if let trip = result.tripTheo {
                            CalculatorTheoBubble(
                                title: "Trip theo",
                                value: formatMoney(abs(trip), symbol: settingsStore.currencySymbol),
                                isPositiveEV: trip < 0,
                                detail: "Daily × days"
                            )
                        }
                    }
                    LoyaltyCalculatorInsightSection(
                        kind: kind,
                        resultSummary: result.insightSummary
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
                }
            }
        }
        .environmentObject(settingsStore)
    }

    private var computed: (adt: Double, tripTheo: Double?, detail: String, insightSummary: String)? {
        let dayCount = parseDouble(days) ?? 1
        switch mode {
        case .fromPlay:
            guard let bet = parseDouble(averageBet),
                  let pace = parseDouble(decisionsPerHour),
                  let hours = parseDouble(hoursPerDay),
                  let magnitude = parseDouble(houseEdge)
            else { return nil }
            let edge = edgeBeneficiary.signedPercent(magnitude: magnitude)
            guard let daily = LoyaltyCalculatorMath.theo(
                averageBet: bet,
                decisionsPerHour: pace,
                hours: hours,
                houseEdgePercent: edge
            ) else { return nil }
            let trip = daily * max(dayCount, 1)
            let adt = LoyaltyCalculatorMath.averageDailyTheo(totalTheo: trip, days: max(dayCount, 1)) ?? daily
            let outcome = adt < 0 ? "ADT (+EV win)" : "ADT"
            return (
                adt,
                dayCount > 1 ? trip : nil,
                "Theo per day from avg bet × pace × hours × edge · \(formatSignedEdgePercent(edge))",
                "\(outcome) \(formatMoney(abs(adt), symbol: settingsStore.currencySymbol))/day from avg bet \(formatMoney(bet, symbol: settingsStore.currencySymbol)), \(pace) decisions/hr, \(hours) hours/day, \(formatSignedEdgePercent(edge)) over \(max(dayCount, 1)) day(s)."
            )
        case .fromTotal:
            guard let total = parseDouble(totalTheo),
                  let adt = LoyaltyCalculatorMath.averageDailyTheo(totalTheo: total, days: dayCount)
            else { return nil }
            let outcome = adt < 0 ? "ADT (+EV win)" : "ADT"
            return (
                adt,
                nil,
                "ADT = total theo ÷ days",
                "\(outcome) \(formatMoney(abs(adt), symbol: settingsStore.currencySymbol))/day from total theo \(formatMoney(total, symbol: settingsStore.currencySymbol)) over \(dayCount) day(s)."
            )
        }
    }
}

// MARK: - Comps

private struct CasinoCompCalculatorForm: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore

    let kind: LoyaltyCalculatorKind

    @State private var theo = ""
    @State private var rematchPercent = "20"

    var body: some View {
        CalculatorFormShell(insightsReady: computed != nil) {
            VStack(alignment: .leading, spacing: 14) {
                L10nText("Many properties return a portion of theo as comps. Rematch rates commonly fall around 10–40%.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))

                CalculatorFieldRow(
                    label: "Theo",
                    text: $theo,
                    suffix: settingsStore.currencySymbol
                )
                CalculatorFieldRow(label: "Rematch rate", text: $rematchPercent, suffix: "%")

                if computed == nil {
                    hintCard("Enter theo and rematch % — then open TierTap AI Insights.")
                }
            }
        } insightsContent: {
            if let comps = computed, let theoValue = parseDouble(theo), let rate = parseDouble(rematchPercent) {
                VStack(alignment: .leading, spacing: 16) {
                    CalculatorTheoBubble(
                        title: "Estimated comps",
                        value: formatMoney(comps, symbol: settingsStore.currencySymbol),
                        isPositiveEV: true,
                        detail: "Comps = theo × rematch % · theo \(formatMoney(theoValue, symbol: settingsStore.currencySymbol)) @ \(rate)%",
                        outcomeCaption: "Rematch value"
                    )
                    LoyaltyCalculatorInsightSection(
                        kind: kind,
                        resultSummary: """
                        Estimated comps \(formatMoney(comps, symbol: settingsStore.currencySymbol)) from theo \(formatMoney(theoValue, symbol: settingsStore.currencySymbol)) at \(rate)% rematch.
                        """
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(subscriptionStore)
                    .environmentObject(authStore)
                }
            }
        }
        .environmentObject(settingsStore)
    }

    private var computed: Double? {
        guard let theoValue = parseDouble(theo),
              let rate = parseDouble(rematchPercent)
        else { return nil }
        return LoyaltyCalculatorMath.estimatedComps(theo: theoValue, rematchPercent: rate)
    }
}

// MARK: - Tier points

private struct CasinoTierCalculatorForm: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore

    let kind: LoyaltyCalculatorKind

    private enum Basis: String, CaseIterable, Identifiable {
        case theo
        case coinIn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .theo: return "From theo"
            case .coinIn: return "From coin-in / rated"
            }
        }
    }

    @State private var basis: Basis = .theo
    @State private var basisAmount = ""
    @State private var pointsPerDollar = "1"
    @State private var multiplier = "1"
    @State private var pointsNeeded = ""

    var body: some View {
        CalculatorFormShell(insightsReady: earnedPoints != nil) {
            VStack(alignment: .leading, spacing: 14) {
                L10nText("Estimate tier credits from theo or rated play using points-per-dollar and any promo multiplier.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))

                Picker("Basis", selection: $basis) {
                    ForEach(Basis.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                CalculatorFieldRow(
                    label: basis == .theo ? "Theo" : "Rated play",
                    text: $basisAmount,
                    suffix: settingsStore.currencySymbol
                )
                CalculatorFieldRow(label: "Pts per $1", text: $pointsPerDollar)
                CalculatorFieldRow(label: "Multiplier", text: $multiplier, suffix: "×")

                Divider().background(Color.white.opacity(0.25))

                Text("Reverse: points still needed")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))

                CalculatorFieldRow(label: "Points needed", text: $pointsNeeded)

                if earnedPoints == nil {
                    hintCard("Fill basis, pts/$, and multiplier — then open TierTap AI Insights.")
                }
            }
        } insightsContent: {
            VStack(alignment: .leading, spacing: 16) {
                if let points = earnedPoints {
                    CalculatorTheoBubble(
                        title: "Tier points",
                        value: formatPoints(points),
                        isPositiveEV: true,
                        detail: "Points = basis × pts/$ × multiplier",
                        outcomeCaption: "Estimated points"
                    )
                }
                if let needed = basisStillNeeded {
                    CalculatorTheoBubble(
                        title: basis == .theo ? "Theo still needed" : "Rated still needed",
                        value: formatMoney(needed, symbol: settingsStore.currencySymbol),
                        isPositiveEV: false,
                        detail: "Basis = points needed ÷ (pts/$ × multiplier)",
                        outcomeCaption: "To reach goal"
                    )
                }
                if let summary = insightSummary {
                    LoyaltyCalculatorInsightSection(kind: kind, resultSummary: summary)
                        .environmentObject(settingsStore)
                        .environmentObject(subscriptionStore)
                        .environmentObject(authStore)
                }
            }
        }
        .environmentObject(settingsStore)
    }

    private var earnedPoints: Double? {
        guard let amount = parseDouble(basisAmount),
              let rate = parseDouble(pointsPerDollar),
              let mult = parseDouble(multiplier)
        else { return nil }
        return LoyaltyCalculatorMath.estimatedTierPoints(
            basisDollars: amount,
            pointsPerDollar: rate,
            multiplier: mult
        )
    }

    private var basisStillNeeded: Double? {
        guard let needed = parseDouble(pointsNeeded),
              let rate = parseDouble(pointsPerDollar),
              let mult = parseDouble(multiplier)
        else { return nil }
        return LoyaltyCalculatorMath.basisNeededForPoints(
            pointsNeeded: needed,
            pointsPerDollar: rate,
            multiplier: mult
        )
    }

    private var insightSummary: String? {
        var parts: [String] = []
        if let points = earnedPoints, let amount = parseDouble(basisAmount) {
            parts.append(
                "Estimated \(formatPoints(points)) tier points from \(basis == .theo ? "theo" : "rated play") \(formatMoney(amount, symbol: settingsStore.currencySymbol)) at \(pointsPerDollar) pts/$ × \(multiplier)x."
            )
        }
        if let needed = basisStillNeeded, let pts = parseDouble(pointsNeeded) {
            parts.append(
                "Still need \(formatPoints(pts)) points → about \(formatMoney(needed, symbol: settingsStore.currencySymbol)) more \(basis == .theo ? "theo" : "rated play")."
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Helpers

private func hintCard(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundColor(.white.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
