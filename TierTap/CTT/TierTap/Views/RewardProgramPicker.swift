import SwiftUI

// MARK: - Catalog (shared check-in, add-past, wallet)

enum RewardProgramsCatalog {
    static let defaultPrograms: [String] = [
        "MGM Rewards",
        "Caesars Rewards",
        "Wynn Rewards",
        "Grazie Rewards",
        "Identity Rewards",
        "B Connected",
        "Club One",
        "Club Serrano"
    ]

    private static let casinoRewardPrograms: [String: [String]] = [
        "MGM": ["MGM Rewards"],
        "Bellagio": ["MGM Rewards"],
        "Aria": ["MGM Rewards"],
        "Cosmopolitan": ["Identity Rewards"],
        "Caesars": ["Caesars Rewards"],
        "Harrah": ["Caesars Rewards"],
        "Paris": ["Caesars Rewards"],
        "Wynn": ["Wynn Rewards"],
        "Encore": ["Wynn Rewards"],
        "Venetian": ["Grazie Rewards"],
        "Palazzo": ["Grazie Rewards"],
        "Palms": ["Club Serrano"],
        "Boyd": ["B Connected"]
    ]

    /// Base suggestions from casino name (or defaults when casino is empty).
    static func basePrograms(forCasino casino: String) -> [String] {
        let trimmed = casino.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultPrograms }
        let matches = casinoRewardPrograms.compactMap { key, programs in
            trimmed.localizedCaseInsensitiveContains(key) ? programs : nil
        }
        let flattened = matches.flatMap { $0 }
        let unique = Array(Set(flattened))
        return unique.isEmpty ? defaultPrograms : unique
    }

    /// Merges casino defaults, user-added names, and programs already used on wallet cards.
    static func mergedPrograms(
        casino: String,
        walletProgramNames: [String],
        customProgramsFromSettings: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func appendUnique(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let key = t.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(t)
        }

        for p in basePrograms(forCasino: casino) { appendUnique(p) }
        for p in customProgramsFromSettings { appendUnique(p) }
        for p in walletProgramNames { appendUnique(p) }
        return result
    }
}

// MARK: - Tier points from wallet “current tier” field

enum WalletTierPointsFormatting {
    /// Maps wallet free-text tier / points into digits for session tier fields.
    static func pointsText(fromWalletTierField text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "0" }
        if let v = Int(t) { return "\(max(0, v))" }
        let digitsOnly = t.filter { $0.isNumber }
        if let v = Int(digitsOnly), !digitsOnly.isEmpty { return "\(max(0, v))" }
        return "0"
    }
}

// MARK: - New program sheet

struct NewRewardProgramNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    let onSave: (String) -> Void

    init(initial: String = "", onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Program name", text: $draft)
            }
            .navigationTitle("New program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        onSave(t)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Check-in row: menu + wallet launcher

struct RewardsProgramPickerRow: View {
    let casino: String
    @Binding var selectedProgram: String
    @Binding var tierPointsText: String
    /// Set when the user picks a card from the wallet at check-in so ending tier can sync back to that card.
    @Binding var linkedWalletCardId: UUID?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var walletStore: RewardWalletStore

    @State private var showNewProgramSheet = false
    @State private var showWalletSelection = false

    private var merged: [String] {
        let walletNames = walletStore.cards.map(\.rewardProgram)
        return RewardProgramsCatalog.mergedPrograms(
            casino: casino,
            walletProgramNames: walletNames,
            customProgramsFromSettings: settingsStore.customRewardPrograms
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Menu {
                Button {
                    selectedProgram = ""
                    linkedWalletCardId = nil
                } label: {
                    L10nText("Select Rewards")
                }
                ForEach(merged, id: \.self) { program in
                    Button(program) {
                        selectedProgram = program
                        linkedWalletCardId = nil
                    }
                }
                Divider()
                Button("New program…") {
                    showNewProgramSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(menuLabelText)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                showWalletSelection = true
            } label: {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose from wallet")
        }
        .sheet(isPresented: $showNewProgramSheet) {
            NewRewardProgramNameSheet { name in
                settingsStore.rememberRewardProgramName(name)
                selectedProgram = name
                linkedWalletCardId = nil
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showWalletSelection) {
            TierTapWalletView(
                rewardsSelectionHandler: { card in
                    let name = card.rewardProgram.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        settingsStore.rememberRewardProgramName(name)
                        selectedProgram = card.rewardProgram
                    }
                    tierPointsText = WalletTierPointsFormatting.pointsText(fromWalletTierField: card.currentTier)
                    linkedWalletCardId = card.id
                    showWalletSelection = false
                }
            )
            .environmentObject(settingsStore)
            .environmentObject(walletStore)
        }
    }

    private var menuLabelText: String {
        let t = selectedProgram.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return L10n.tr("Select Rewards", language: settingsStore.appLanguage)
        }
        return t
    }
}

// MARK: - Wallet card editor — same presets + typing

struct RewardProgramFieldWithSharedPresets: View {
    /// Pass check-in casino when editing from session flows; use `""` in wallet-only editors.
    let casino: String
    @Binding var programText: String

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var walletStore: RewardWalletStore

    @State private var showNewProgramSheet = false

    private var merged: [String] {
        let walletNames = walletStore.cards.map(\.rewardProgram)
        return RewardProgramsCatalog.mergedPrograms(
            casino: casino,
            walletProgramNames: walletNames,
            customProgramsFromSettings: settingsStore.customRewardPrograms
        )
    }

    var body: some View {
        Group {
            Menu {
                ForEach(merged, id: \.self) { program in
                    Button(program) {
                        programText = program
                    }
                }
                Divider()
                Button("New program…") {
                    showNewProgramSheet = true
                }
            } label: {
                HStack {
                    Text("Reward program presets")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            TextField("Reward program", text: $programText)
        }
        .sheet(isPresented: $showNewProgramSheet) {
            NewRewardProgramNameSheet { name in
                settingsStore.rememberRewardProgramName(name)
                programText = name
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Wallet tier closeout toast (app-wide overlay)

struct WalletTierCloseoutToastBanner: View {
    let fromPoints: Int
    let toPoints: Int

    @State private var tickOrigin: Date?

    private var delta: Int { toPoints - fromPoints }
    private var isUp: Bool { delta > 0 }

    var body: some View {
        ZStack {
            Color(white: 0.25).opacity(0.92)
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let elapsed = tickOrigin.map { context.date.timeIntervalSince($0) } ?? 0
                let (displayed, phase) = Self.displayPhase(
                    elapsed: elapsed,
                    from: fromPoints,
                    to: toPoints
                )

                VStack(spacing: 16) {
                    Text("TierTap tier points changed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Text(displayed.formatted(.number.grouping(.automatic)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()

                    Group {
                        switch phase {
                        case .counting:
                            Text("Updating your wallet card to match this session.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.72))
                        case .holding:
                            Text("Your wallet now shows this TierTap balance.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        Text(fromPoints.formatted(.number.grouping(.automatic)))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundColor(.white.opacity(0.55))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isUp ? .green.opacity(0.9) : .orange.opacity(0.9))
                        Text(toPoints.formatted(.number.grouping(.automatic)))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white.opacity(0.95))
                    }

                    Text("\(isUp ? "Up" : "Down") \(abs(delta).formatted(.number.grouping(.automatic))) pts")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isUp ? .green : .orange)
                }
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: 380)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(white: 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            tickOrigin = Date()
            CelebrationPlayer.shared.playTierChangeCoins()
        }
    }

    private enum CountPhase {
        case counting
        case holding
    }

    /// Eased progress 0…1: velocity is low at the ends and higher in the middle (slow → fast → slow).
    private static func easeInOutQuint(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        if x < 0.5 {
            return 16 * x * x * x * x * x
        }
        let u = -2 * x + 2
        return 1 - (u * u * u * u * u) / 2
    }

    private static func displayPhase(elapsed: TimeInterval, from: Int, to: Int) -> (displayed: Int, phase: CountPhase) {
        let count = WalletTierCloseoutTiming.countDuration
        let hold = WalletTierCloseoutTiming.holdOnFinalDuration
        if elapsed < count {
            let rawT = min(1, elapsed / count)
            let eased = easeInOutQuint(rawT)
            let interpolated = Double(from) + Double(to - from) * eased
            return (Int(interpolated.rounded(.toNearestOrAwayFromZero)), .counting)
        }
        if elapsed < count + hold {
            return (to, .holding)
        }
        return (to, .holding)
    }
}
