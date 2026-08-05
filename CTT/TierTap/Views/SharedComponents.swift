import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit
import CoreLocation
import Supabase

#if os(iOS)
/// Use with `sheet(item:)` so the share UI is only created once the image exists (avoids empty `UIActivityViewController` on first open).
struct ShareableImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Bitmap scale / layout width for `ImageRenderer` and similar share exports (not session‑art CoreGraphics).
enum ShareImageExportQuality {
    /// Supersample share PNGs beyond default screen scale where the GPU can still raster cleanly.
    @MainActor static var imageRendererScale: CGFloat {
        min(4, max(3, UIScreen.main.nativeScale))
    }

    /// Logical width (points) for wide share cards before `imageRendererScale` is applied.
    @MainActor static var wideCardWidthPoints: CGFloat {
        let w = UIScreen.main.bounds.width
        return min(960, max(440, w - 20)).rounded(.down)
    }
}
#endif

struct DarkTextFieldStyle: TextFieldStyle {
    var textColor: Color = .white
    var accentColor: Color = .green

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemGray6).opacity(0.25))
            .foregroundColor(textColor)
            .cornerRadius(10)
            .tint(accentColor)
    }
}

/// Larger green capsule used for filter panels (e.g. history, community feed, analytics date row).
struct FilterPanelPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.28))
                .foregroundColor(.green)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Strong primary styling for TierTap Plus token purchase so it reads as a tappable CTA vs stat chips.
struct TierTapPlusPurchaseButtonChrome: ViewModifier {
    var compact: Bool = false

    func body(content: Content) -> some View {
        let corner: CGFloat = compact ? 11 : 12
        content
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 12)
            .padding(.horizontal, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.78, blue: 0.48),
                        Color(red: 0.05, green: 0.48, blue: 0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.42), radius: compact ? 4 : 6, x: 0, y: compact ? 2 : 3)
    }
}

extension View {
    func tierTapPlusPurchaseButtonChrome(compact: Bool = false) -> some View {
        modifier(TierTapPlusPurchaseButtonChrome(compact: compact))
    }
}

// MARK: - Date + time split for compact filter pickers

extension Binding where Value == Date {
    /// Calendar day for a `.date` picker; preserves hour/minute/second of the full `Date` when the day changes.
    func datePortion(calendar: Calendar = .current) -> Binding<Date> {
        Binding(
            get: { calendar.startOfDay(for: self.wrappedValue) },
            set: { newDay in
                let time = calendar.dateComponents([.hour, .minute, .second], from: self.wrappedValue)
                var components = calendar.dateComponents([.year, .month, .day], from: newDay)
                components.hour = time.hour
                components.minute = time.minute
                components.second = time.second
                if let merged = calendar.date(from: components) {
                    self.wrappedValue = merged
                }
            }
        )
    }

    /// Time-of-day for an `.hourAndMinute` picker; merges into the calendar day of the full `Date`.
    func timePortion(calendar: Calendar = .current) -> Binding<Date> {
        Binding(
            get: {
                let comps = calendar.dateComponents([.hour, .minute], from: self.wrappedValue)
                return calendar.date(from: DateComponents(calendar: calendar, year: 2000, month: 1, day: 1, hour: comps.hour, minute: comps.minute))
                    ?? self.wrappedValue
            },
            set: { newTime in
                let day = calendar.dateComponents([.year, .month, .day], from: self.wrappedValue)
                let time = calendar.dateComponents([.hour, .minute], from: newTime)
                var merged = DateComponents()
                merged.year = day.year
                merged.month = day.month
                merged.day = day.day
                merged.hour = time.hour
                merged.minute = time.minute
                if let d = calendar.date(from: merged) {
                    self.wrappedValue = d
                }
            }
        )
    }
}

struct GameButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 4)
                .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(10)
        }
    }
}

/// Full-width control that opens the game list — wide text area (scales down before truncating) and layered gradients.
struct GamePickerSelectorRow: View {
    @EnvironmentObject var settingsStore: SettingsStore
    let title: String
    /// Stronger green accent when the current selection is outside the quick-pick list (Check In).
    var accentHighlighted: Bool = false
    var isPlaceholder: Bool = false
    var showSearchIcon: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showSearchIcon {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(isPlaceholder ? Color.gray.opacity(0.9) : Color.white.opacity(0.95))
                }
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(isPlaceholder ? Color.gray.opacity(0.95) : (accentHighlighted ? Color.white : Color.white.opacity(0.95)))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(isPlaceholder ? 0.35 : 0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectorFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color.white.opacity(0.05),
                                        settingsStore.secondaryColor.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var selectorFill: LinearGradient {
        if accentHighlighted {
            return LinearGradient(
                stops: [
                    .init(color: Color.green.opacity(0.42), location: 0),
                    .init(color: settingsStore.secondaryColor.opacity(0.4), location: 0.52),
                    .init(color: settingsStore.primaryColor.opacity(0.32), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            stops: [
                .init(color: settingsStore.primaryColor.opacity(0.52), location: 0),
                .init(color: settingsStore.secondaryColor.opacity(0.4), location: 0.45),
                .init(color: settingsStore.primaryColor.opacity(0.26), location: 0.78),
                .init(color: settingsStore.secondaryColor.opacity(0.22), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Optional machine notes when game type is Slots.
struct SlotSessionNotesOnlySection: View {
    @Binding var slotNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            L10nText("Notes (optional)")
                .font(.caption2)
                .foregroundColor(.gray)
            TextField("Denom, room, machine notes…", text: $slotNotes, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(DarkTextFieldStyle())
        }
    }
}

/// Gradient fill, border, and shadows matching `GameCategoryWheelPicker`’s chrome.
struct GameCategoryBubbleBackground: View {
    @EnvironmentObject var settingsStore: SettingsStore
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: settingsStore.primaryColor.opacity(0.48), location: 0.45),
                            .init(color: Color.black.opacity(0.42), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.82),
                            Color.white.opacity(0.38),
                            settingsStore.secondaryColor.opacity(0.68),
                            settingsStore.primaryColor.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
        }
        .shadow(color: Color.green.opacity(0.42), radius: 14, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}

/// Table games vs Slots vs Poker — **horizontal** selector inside the same gradient “bubble” (distinct from Cash/Tournament pills).
struct GameCategoryWheelPicker: View {
    @Binding var selection: SessionGameCategory
    @EnvironmentObject var settingsStore: SettingsStore
    var heading: String = "Game Type"
    var compactHeading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !heading.isEmpty {
                Text(heading)
                    .font(compactHeading ? .caption.bold() : .subheadline.bold())
                    .foregroundColor(.white)
            }
            HStack(spacing: 0) {
                ForEach(SessionGameCategory.allCases, id: \.self) { cat in
                    categorySegment(cat)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameCategoryBubbleBackground(cornerRadius: 16))
    }

    private func categorySegment(_ cat: SessionGameCategory) -> some View {
        let isSelected = selection == cat
        return Button {
            selection = cat
        } label: {
            Text(cat.pickerTitle)
                .font(compactHeading ? .caption.bold() : .subheadline.bold())
                .foregroundColor(isSelected ? .black : .white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compactHeading ? 8 : 10)
                .padding(.horizontal, 4)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green, Color.green.opacity(0.88)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

struct InputRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    /// English title on the numeric dial pad; `nil` = text field only (no keypad button).
    var dialPadNavigationTitle: String? = nil
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold()).foregroundColor(.white)
            if let dialTitle = dialPadNavigationTitle {
                NumericEntryWithDialPad(
                    placeholder: placeholder,
                    text: $value,
                    dialPadNavigationTitle: dialTitle
                )
            } else {
                TextField(placeholder, text: $value)
                    .textFieldStyle(DarkTextFieldStyle())
                    .keyboardType(.numberPad)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

struct SummaryRow: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.gray)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundColor(color)
        }
    }
}

struct StatMini: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.gray)
            Text(value).font(.title3.bold()).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

struct DetailSection<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundColor(.white)
            Divider().background(Color.gray.opacity(0.3))
            content
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct DetailRow: View {
    let label: String; let value: String
    var valueColor: Color = .white; var bold: Bool = false
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.gray)
            Spacer()
            Text(value).font(bold ? .subheadline.bold() : .subheadline).foregroundColor(valueColor)
        }
    }
}

/// Horizontal quick-select chips for common amounts (e.g. under Avg Bet Actual/Rated).
struct CommonAmountButtons: View {
    let amounts: [Int]
    @Binding var selected: String
    @EnvironmentObject var settingsStore: SettingsStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(amounts, id: \.self) { amt in
                    Button("\(settingsStore.currencySymbol)\(amt)") { selected = "\(amt)" }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected == "\(amt)" ? Color.green : Color(.systemGray6).opacity(0.25))
                        .foregroundColor(selected == "\(amt)" ? .black : .white)
                        .cornerRadius(8)
                }
            }
        }
    }
}

/// Whether the picker lists table games (with optional API-expanded names) or slot titles only.
enum GamePickerMode {
    case table
    case slots
}

struct GamePickerView: View {
    @Binding var selectedGame: String
    var mode: GamePickerMode = .table
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    @State private var dynamicGames: [String] = []
    @State private var isLoading = false

    /// Supabase `TableGames` catalog sync — only for signed-in Pro (or subscription override).
    private var canLoadCloudGameNames: Bool {
        authStore.isSignedIn
            && (subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive)
    }

    private var favorites: [String] {
        switch mode {
        case .table: return settingsStore.favoriteGames
        case .slots: return settingsStore.favoriteSlotGames
        }
    }

    private var allGamesUnion: [String] {
        switch mode {
        case .table:
            let hardCoded = GamesList.all
            let combined = Set(hardCoded + dynamicGames)
            return Array(combined).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .slots:
            return SlotsList.all
        }
    }

    private var filteredAll: [String] {
        let base = allGamesUnion
        guard !search.isEmpty else { return base }
        return base.filter { $0.lowercased().contains(search.lowercased()) }
    }
    private var filteredFavorites: [String] {
        search.isEmpty ? favorites : favorites.filter { $0.lowercased().contains(search.lowercased()) }
    }
    private var filteredOthers: [String] {
        let favSet = Set(favorites)
        return filteredAll.filter { !favSet.contains($0) }
    }

    /// Slot picker: offer using typed search text as the game name when it is not an exact list match.
    private var slotsCustomNameFromSearch: String? {
        guard mode == .slots else { return nil }
        let t = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let exactInList = allGamesUnion.contains { $0.caseInsensitiveCompare(t) == .orderedSame }
        return exactInList ? nil : t
    }

    var body: some View {
        NavigationStack {
            ZStack {
                gamePickerListBackdrop.ignoresSafeArea()
                List {
                    if isLoading {
                        ProgressView("Loading games…")
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                    }
                    if let custom = slotsCustomNameFromSearch {
                        Section {
                            Button {
                                selectedGame = custom
                                dismiss()
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "pencil.line")
                                        .foregroundColor(.green)
                                    Text("Use “\(custom)”")
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.green.opacity(0.22), location: 0),
                                        .init(color: Color.white.opacity(0.06), location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        } header: {
                            L10nText("Not in list")
                                .foregroundColor(.gray)
                        }
                    }
                    if !filteredFavorites.isEmpty {
                        Section("Favorites") {
                            ForEach(filteredFavorites, id: \.self) { game in
                                gameRow(game)
                            }
                        }
                    }
                    Section(filteredFavorites.isEmpty ? (mode == .slots ? "Slot games" : "Games") : (mode == .slots ? "All slot games" : "All games")) {
                        ForEach(filteredOthers, id: \.self) { game in
                            gameRow(game)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            .searchable(text: $search, prompt: mode == .slots ? "Search or type a custom name" : "Search games")
            .navigationTitle(mode == .slots ? "Select Slot Game" : "Select Game").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(
                    stops: [
                        .init(color: settingsStore.primaryColor.opacity(0.92), location: 0),
                        .init(color: settingsStore.secondaryColor.opacity(0.78), location: 0.45),
                        .init(color: settingsStore.primaryColor.opacity(0.65), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .task(id: "\(mode == .table)-\(canLoadCloudGameNames)") {
                guard mode == .table else { return }
                if canLoadCloudGameNames {
                    await loadDynamicGames()
                } else {
                    await MainActor.run {
                        dynamicGames = []
                        isLoading = false
                    }
                }
            }
        }
    }

    /// Layered gradients behind the searchable list (richer than a single two-stop gradient).
    private var gamePickerListBackdrop: some View {
        ZStack {
            settingsStore.primaryGradient
            LinearGradient(
                stops: [
                    .init(color: settingsStore.secondaryColor.opacity(0.55), location: 0),
                    .init(color: Color.clear, location: 0.52),
                    .init(color: settingsStore.primaryColor.opacity(0.45), location: 1)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.07), location: 0),
                    .init(color: Color.clear, location: 0.35),
                    .init(color: Color.black.opacity(0.18), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
        }
    }

    private func gameRow(_ game: String) -> some View {
        Button {
            selectedGame = game
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(game)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selectedGame == game {
                    Image(systemName: "checkmark").foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.14), location: 0),
                    .init(color: Color.white.opacity(0.04), location: 0.55),
                    .init(color: settingsStore.secondaryColor.opacity(0.12), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func loadDynamicGames() async {
        guard canLoadCloudGameNames else { return }
        guard !isLoading else { return }
        isLoading = true
        let names = await TableGamesAPI.loadDistinctNames()
        await MainActor.run {
            dynamicGames = names
            isLoading = false
        }
    }
}

extension View {
    /// Prefer large height so the list uses full width; medium remains available when dragging.
    func gamePickerSheetPresentation() -> some View {
        presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - Free Play Analytics

/// Summarizes logged free play and value-adjusted ROI (analytics only; excluded from win/loss).
struct FreePlaySummaryCard: View {
    let sessions: [Session]
    let gradient: LinearGradient
    let currencySymbol: String
    let dateRangeText: String?

    private var closedWithWL: [Session] {
        sessions.filter { $0.winLoss != nil }
    }

    private var totalFreePlay: Int {
        closedWithWL.map(\.totalFreePlay).reduce(0, +)
    }

    private var totalCashBuyIn: Int {
        closedWithWL.map(\.totalBuyIn).reduce(0, +)
    }

    private var totalCashNet: Int {
        closedWithWL.compactMap(\.winLoss).reduce(0, +)
    }

    private var cashROIPercent: Double? {
        let initialSum = closedWithWL.compactMap(\.initialBuyIn).reduce(0, +)
        guard initialSum > 0 else { return nil }
        return (Double(totalCashNet) / Double(initialSum)) * 100.0
    }

    private var valueAdjustedROIPercent: Double? {
        guard totalCashBuyIn > 0 else { return nil }
        return (Double(totalCashNet + totalFreePlay) / Double(totalCashBuyIn)) * 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                L10nText("Free Play")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if let range = dateRangeText {
                    Text(range)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            Text("Excluded from win/loss, session ROI, and tax. Value-adjusted ROI is for analytics only.")
                .font(.caption2)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                MetricPill(
                    title: "Total free play",
                    value: "\(currencySymbol)\(totalFreePlay.formatted(.number.grouping(.automatic)))",
                    color: totalFreePlay > 0 ? .green : .gray
                )
                if let roi = cashROIPercent {
                    MetricPill(
                        title: "Cash ROI",
                        value: String(format: "%.1f%%", roi),
                        color: roi >= 0 ? .green : .red
                    )
                }
                if let adj = valueAdjustedROIPercent, totalFreePlay > 0 {
                    MetricPill(
                        title: "Value ROI",
                        value: String(format: "%.1f%%", adj),
                        color: adj >= 0 ? .green : .red
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Poker Analytics Shared Components

/// Poker-focused summary metrics card (win rate, hourly, ROI).
struct PokerPerformanceSummaryCard: View {
    let sessions: [Session]
    let gradient: LinearGradient
    let currencySymbol: String
    let dateRangeText: String?
    let locationFilterText: String?
    /// When true, net, hourly, ROI, and win rate use EV (cash + comps); when false, cash net only.
    var useExpectedValue: Bool = false

    private var closedWithWL: [Session] {
        sessions.filter { $0.winLoss != nil && $0.gameCategory == .poker }
    }

    private func outcome(_ s: Session) -> Int {
        s.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0
    }

    private var totalProfit: Int {
        closedWithWL.map { outcome($0) }.filter { $0 > 0 }.reduce(0, +)
    }

    private var totalLoss: Int {
        abs(closedWithWL.map { outcome($0) }.filter { $0 < 0 }.reduce(0, +))
    }

    private var totalHours: Double {
        closedWithWL.reduce(0.0) { $0 + $1.hoursPlayed }
    }

    private var hourlyRate: Double? {
        let net = closedWithWL.map { outcome($0) }.reduce(0, +)
        guard totalHours > 0 else { return nil }
        return Double(net) / totalHours
    }

    private var roiPercent: Double? {
        let totalInitial = closedWithWL.compactMap { $0.initialBuyIn }.reduce(0, +)
        guard totalInitial > 0 else { return nil }
        let net = closedWithWL.map { outcome($0) }.reduce(0, +)
        return (Double(net) / Double(totalInitial)) * 100.0
    }

    private var totalFreePlayLogged: Int {
        closedWithWL.map(\.totalFreePlay).reduce(0, +)
    }

    private var winRate: Double? {
        let wins = closedWithWL.filter { outcome($0) > 0 }.count
        guard !closedWithWL.isEmpty else { return nil }
        return Double(wins) / Double(closedWithWL.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                L10nText("Poker Performance")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if let range = dateRangeText {
                    Text(range)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            if useExpectedValue {
                L10nText("Basis: EV (cash net + comps)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 12) {
                let net = totalProfit - totalLoss
                MetricPill(
                    title: "Net",
                    value: "\(currencySymbol)\(net)",
                    color: net >= 0 ? .green : .red
                )
                if let hr = hourlyRate {
                    let amt = Int(round(hr))
                    MetricPill(
                        title: "Hourly",
                        value: "\(amt >= 0 ? "+" : "-")\(currencySymbol)\(abs(amt))",
                        color: amt >= 0 ? .green : .red
                    )
                }
                if let roi = roiPercent {
                    MetricPill(
                        title: "ROI",
                        value: String(format: "%.1f%%", roi),
                        color: roi >= 0 ? .green : .red
                    )
                }
            }

            if let wr = winRate {
                Text("Win rate: \(String(format: "%.0f%%", wr * 100)) over \(closedWithWL.count) sessions")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if totalFreePlayLogged > 0 {
                Text("Free play logged: \(currencySymbol)\(totalFreePlayLogged.formatted(.number.grouping(.automatic))) (not in net or ROI above)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

/// Poker ROI trend "chart" – summarizes ROI distribution over time.
struct PokerROITrendChartCard: View {
    let sessions: [Session]
    let gradient: LinearGradient
    let currencySymbol: String
    let dateRangeText: String?
    let locationFilterText: String?
    var useExpectedValue: Bool = false

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let roi: Double
    }

    private var points: [Point] {
        let poker = sessions
            .filter { $0.gameCategory == .poker && $0.winLoss != nil && ($0.initialBuyIn ?? 0) > 0 }
            .sorted { $0.startTime < $1.startTime }
        return poker.compactMap { s in
            guard let bi = s.initialBuyIn, bi > 0 else { return nil }
            let numer = Double(s.analyticsOutcome(useExpectedValue: useExpectedValue) ?? 0)
            let roi = (numer / Double(bi)) * 100.0
            return Point(date: s.startTime, roi: roi)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                L10nText("Poker ROI Over Time")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            if useExpectedValue {
                L10nText("Per session: EV (cash + comps) ÷ initial buy-in")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            if points.isEmpty {
                L10nText("Add a few poker sessions to see ROI trends over time.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                let values = points.map { $0.roi }
                let avg = values.reduce(0, +) / Double(values.count)
                if let min = values.min(), let max = values.max() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Avg ROI: %.1f%%", avg))
                            .font(.subheadline)
                            .foregroundColor(avg >= 0 ? .green : .red)
                        Text(String(format: "Range: %.1f%% to %.1f%%", min, max))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Tier points wheel (0 to 999,999, step 1000)
struct TierPointsWheel: View {
    @Binding var selectedValue: String
    private static let step = 1000
    private static let maxVal = 999_999
    private static let values: [Int] = stride(from: 0, through: maxVal, by: step).map { $0 }
    @State private var wheelIndex: Int = 0

    private func syncWheelIndexFromSelectedValue() {
        let v = Int(selectedValue) ?? 0
        let idx = Self.values.firstIndex(where: { $0 >= v }) ?? 0
        wheelIndex = min(idx, Self.values.count - 1)
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            Picker("Tier points", selection: $wheelIndex) {
                ForEach(Array(Self.values.enumerated()), id: \.offset) { idx, val in
                    Text("\(val)").tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .clipped()
            .onChange(of: wheelIndex) { _, new in
                selectedValue = "\(Self.values[new])"
            }
            .onAppear {
                syncWheelIndexFromSelectedValue()
            }
            .onChange(of: selectedValue) { _ in
                syncWheelIndexFromSelectedValue()
            }
        } else {
            // Fallback on earlier versions
        }
    }
}

// MARK: - Starting tier points quick pick (1k–50k grid sheet + exact field)

private enum StartingTierAuxSheet: String, Identifiable {
    case quickPickGrid
    case dialPad
    var id: String { rawValue }
}

/// Shared on-screen digit grid for currency and other numeric entry.
struct NumericKeypadGrid: View {
    @Binding var digits: String
    var maxDigits: Int = 12

    private func appendDigit(_ d: String) {
        guard d.count == 1, d.first?.isNumber == true else { return }
        guard digits.count < maxDigits else { return }
        digits.append(d)
    }

    private func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    private func clearAll() {
        digits = ""
    }

    private func dialButton(_ title: String) -> some View {
        Button {
            appendDigit(title)
        } label: {
            Text(title)
                .font(.title.bold())
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(Color(.systemGray6).opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { n in
                        dialButton("\(n)")
                    }
                }
            }
            HStack(spacing: 12) {
                Button(action: deleteLast) {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(Color(.systemGray6).opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                dialButton("0")
                Button(action: clearAll) {
                    L10nText("Clear")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(Color(.systemGray6).opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }
}

/// Numeric pad (digits only). ~60% screen height; keys aligned toward the bottom. `navigationTitle` is the English source for localization.
struct NumericDialPadSheet: View {
    @Binding var value: String
    let navigationTitle: String
    /// When true, the large preview uses locale-aware thousands grouping (e.g. 1,234).
    var formatPreviewWithGrouping: Bool = false
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var digits: String = ""

    private var previewText: String {
        let digitRun = digits.isEmpty ? "0" : digits
        if formatPreviewWithGrouping, let n = Int(digitRun) {
            return n.formatted(.number.grouping(.automatic))
        }
        return digitRun
    }

    private func applyValueAndDismiss() {
        if digits.isEmpty {
            value = ""
        } else if let n = Int(digits) {
            value = "\(n)"
        }
        dismiss()
    }

    @ViewBuilder
    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 20) {
                    Spacer(minLength: 0)
                    Text(previewText)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)

                    NumericKeypadGrid(digits: $digits)
                }
                .padding()
            }
            .localizedNavigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: applyValueAndDismiss) {
                        L10nText("Done")
                    }
                    .foregroundColor(.green)
                }
            }
            .onAppear {
                digits = value.filter { $0.isNumber }
            }
        }
    }

    var body: some View {
        navigationContent
            .presentationDetents([.fraction(0.6)])
            .presentationDragIndicator(.visible)
    }
}

/// Fast close-out: enter total cash-out on a bottom sheet, then save as an unverified session.
struct FastCloseOutCashSheet: View {
    let defaultCashOut: Int
    let totalBuyIn: Int
    let onCloseOut: (Int) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var digits: String = ""

    private var parsedCashOut: Int? {
        if digits.isEmpty { return 0 }
        return Int(digits)
    }

    private var previewAmount: Int {
        parsedCashOut ?? defaultCashOut
    }

    private var previewColor: Color {
        previewAmount > 0 ? .green : .red
    }

    private var previewWinLoss: Int {
        previewAmount - totalBuyIn
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    Text("\(settingsStore.currencySymbol)\(previewAmount.formatted(.number.grouping(.automatic)))")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundColor(previewColor)
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)

                    HStack(spacing: 24) {
                        VStack(spacing: 4) {
                            L10nText("Buy-in").font(.subheadline).foregroundColor(.gray)
                            Text("\(settingsStore.currencySymbol)\(totalBuyIn.formatted(.number.grouping(.automatic)))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        VStack(spacing: 4) {
                            L10nText("W/L").font(.subheadline).foregroundColor(.gray)
                            Text(previewWinLoss >= 0
                                 ? "+\(settingsStore.currencySymbol)\(previewWinLoss.formatted(.number.grouping(.automatic)))"
                                 : "-\(settingsStore.currencySymbol)\(abs(previewWinLoss).formatted(.number.grouping(.automatic)))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(previewWinLoss >= 0 ? .green : .red)
                        }
                    }

                    NumericKeypadGrid(digits: $digits)

                    Button {
                        guard let cashOut = parsedCashOut else { return }
                        onCloseOut(max(0, cashOut))
                        dismiss()
                    } label: {
                        LocalizedLabel(title: "Close Out", systemImage: "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(parsedCashOut != nil ? Color.green : Color.gray)
                            .foregroundColor(parsedCashOut != nil ? .black : .white)
                            .cornerRadius(14)
                    }
                    .disabled(parsedCashOut == nil)
                }
                .padding()
            }
            .localizedNavigationTitle("Total Cash Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
            .onAppear {
                digits = "\(max(0, defaultCashOut))"
            }
        }
        .presentationDetents([.fraction(0.68)])
        .presentationDragIndicator(.visible)
    }
}

/// Square-grid button that opens the numeric dial pad (shared styling).
struct DialPadLaunchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6).opacity(0.35))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number pad")
    }
}

/// Single-line numeric `TextField` with keyboard + adjacent dial pad sheet.
struct NumericEntryWithDialPad: View {
    let placeholder: String
    @Binding var text: String
    /// English string for `NumericDialPadSheet` navigation title / localization.
    let dialPadNavigationTitle: String
    var textFieldMinWidth: CGFloat?
    var textFieldMaxWidth: CGFloat?

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var showDialPad = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(DarkTextFieldStyle())
                .keyboardType(.numberPad)
                .frame(
                    minWidth: textFieldMinWidth ?? 0,
                    maxWidth: textFieldMaxWidth ?? .infinity,
                    alignment: .leading
                )

            DialPadLaunchButton { showDialPad = true }
        }
        .sheet(isPresented: $showDialPad) {
            NumericDialPadSheet(value: $text, navigationTitle: dialPadNavigationTitle)
                .environmentObject(settingsStore)
        }
    }
}

// MARK: - Tier points tracking warning

enum TierPointsTracking {
    /// True when tier field is empty, non-numeric, or zero or negative.
    static func needsTrackingWarning(for text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return true }
        guard let t = Int(s) else { return true }
        return t <= 0
    }
}

/// Branded confirmation sheet with high-contrast action buttons (matches comp estimate and other TierTap pop-ups).
struct TierTapConfirmationSheet: View {
    let title: String
    let message: String
    var cancelTitle: String = "Cancel"
    let confirmTitle: String
    var confirmIsDestructive: Bool = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text(L10n.tr(message, language: language))
                                .font(.body)
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                            onCancel()
                        } label: {
                            Text(L10n.tr(cancelTitle, language: language))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.white.opacity(0.22))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text(L10n.tr(confirmTitle, language: language))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(confirmIsDestructive ? Color.red : Color.green)
                                .foregroundColor(confirmIsDestructive ? .white : .black)
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .background(Color.black.opacity(0.12))
                }
            }
            .localizedNavigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// Quick-pick grid (1k–50k) plus exact field and dial pad for tier points (starting or ending).
struct TierPointsQuickPickRow: View {
    @Binding var tierPointsText: String
    @State private var auxSheet: StartingTierAuxSheet?
    @EnvironmentObject var settingsStore: SettingsStore

    private var displayPoints: Int? {
        let v = Int(tierPointsText) ?? 0
        return v > 0 ? v : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                auxSheet = .quickPickGrid
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                    Group {
                        if let pts = displayPoints {
                            Text("\(pts.formatted(.number.grouping(.automatic))) pts")
                        } else {
                            L10nText("Quick pick (1k–50k)")
                        }
                    }
                    .lineLimit(1)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6).opacity(0.25))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                TextField("Exact value", text: $tierPointsText)
                    .textFieldStyle(DarkTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(minWidth: 80, maxWidth: 118)

                DialPadLaunchButton { auxSheet = .dialPad }
            }
        }
        .sheet(item: $auxSheet) { kind in
            switch kind {
            case .quickPickGrid:
                TierPointsQuickPickSheet(selectedValue: $tierPointsText)
                    .environmentObject(settingsStore)
            case .dialPad:
                NumericDialPadSheet(value: $tierPointsText, navigationTitle: "Tier points")
                    .environmentObject(settingsStore)
            }
        }
    }
}

private struct TierPointsQuickPickSheet: View {
    @Binding var selectedValue: String
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var showDialPad = false

    private static let gridValues: [Int] = Array(stride(from: 1_000, through: 50_000, by: 1_000))

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @ViewBuilder
    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            TextField("Exact value", text: $selectedValue)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)

                            DialPadLaunchButton { showDialPad = true }
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ],
                            spacing: 12
                        ) {
                            ForEach(Self.gridValues, id: \.self) { pts in
                                Button {
                                    selectedValue = "\(pts)"
                                    dismiss()
                                } label: {
                                    Text(pts.formatted(.number.grouping(.automatic)))
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 56)
                                        .background(Color(.systemGray6).opacity(0.35))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .localizedNavigationTitle("Tier points")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
        }
    }

    var body: some View {
        Group {
            if isPad {
                GeometryReader { geo in
                    navigationContent
                        .frame(height: geo.size.height * 0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                navigationContent
            }
        }
        .sheet(isPresented: $showDialPad) {
            NumericDialPadSheet(value: $selectedValue, navigationTitle: "Tier points")
                .environmentObject(settingsStore)
        }
    }
}

// MARK: - Initial buy-in grid (popup with big squares)

/// Shared multi-select chip grid for buy-in and dollars/credits comp entry.
enum BuyInGridSheetMode: Equatable {
    case initialBuyIn
    case freePlay
    case compAmount
    case stackAmount
}

struct BuyInGridSheet: View {
    let amounts: [Int]
    @Binding var selected: String
    var mode: BuyInGridSheetMode = .initialBuyIn
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedAmounts: Set<Int> = []

    private var totalSelected: Int {
        selectedAmounts.reduce(0, +)
    }

    private var navigationTitle: String {
        switch mode {
        case .initialBuyIn: return "Initial Buy-In"
        case .freePlay: return "Free Play"
        case .compAmount: return "Comp amount"
        case .stackAmount: return "Stack"
        }
    }

    private var totalSummaryText: String {
        let sym = settingsStore.currencySymbol
        switch mode {
        case .initialBuyIn:
            return totalSelected > 0
                ? "Total buy-in: \(sym)\(totalSelected)"
                : "Select one or more amounts."
        case .freePlay:
            return totalSelected > 0
                ? "Free play: \(sym)\(totalSelected)"
                : "Select one or more amounts (optional)."
        case .compAmount:
            return totalSelected > 0
                ? "Comp amount: \(sym)\(totalSelected)"
                : "Select one or more amounts."
        case .stackAmount:
            return totalSelected > 0
                ? "Stack total: \(sym)\(totalSelected)"
                : "Select one or more amounts."
        }
    }

    private var confirmButtonTitle: String {
        let sym = settingsStore.currencySymbol
        switch mode {
        case .initialBuyIn:
            return totalSelected > 0
                ? "Good Luck - Buying in for \(sym)\(totalSelected)"
                : "Good Luck"
        case .freePlay:
            return totalSelected > 0
                ? "Use \(sym)\(totalSelected)"
                : "Set amount"
        case .compAmount:
            return totalSelected > 0
                ? "Use \(sym)\(totalSelected)"
                : "Set amount"
        case .stackAmount:
            return totalSelected > 0
                ? "Use \(sym)\(totalSelected)"
                : "Set stack"
        }
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @ViewBuilder
    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: 12
                        ) {
                            ForEach(amounts, id: \.self) { amt in
                                Button {
                                    if selectedAmounts.contains(amt) {
                                        selectedAmounts.remove(amt)
                                    } else {
                                        selectedAmounts.insert(amt)
                                    }
                                } label: {
                                    Text("\(settingsStore.currencySymbol)\(amt)")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 56)
                                        .background(
                                            selectedAmounts.contains(amt)
                                            ? Color.green
                                            : Color(.systemGray6).opacity(0.35)
                                        )
                                        .foregroundColor(selectedAmounts.contains(amt) ? .black : .white)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                    }

                    VStack(spacing: 8) {
                        Text(totalSummaryText)
                        .font(.subheadline)
                        .foregroundColor(.gray)

                        Button {
                            guard totalSelected > 0 else { return }
                            selected = "\(totalSelected)"
                            dismiss()
                        } label: {
                            Text(confirmButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(totalSelected > 0 ? Color.green : Color.gray)
                            .foregroundColor(totalSelected > 0 ? .black : .white)
                            .cornerRadius(14)
                        }
                        .disabled(totalSelected == 0)
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .localizedNavigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
        }
    }

    var body: some View {
        Group {
            if isPad {
                GeometryReader { geo in
                    navigationContent
                        .frame(height: geo.size.height * 0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                navigationContent
            }
        }
        .onAppear {
            if let current = Int(selected), current > 0 {
                if amounts.contains(current) {
                    selectedAmounts.insert(current)
                }
            }
        }
    }
}

// MARK: - Live Buy-In Sheet

struct BuyInQuickAddSheet: View {
    let quickBuyIns: [Int]
    let onAdd: (Int) -> Void
    /// When set, shows a secondary action to log free play from this sheet.
    var onAddFreePlay: (() -> Void)? = nil
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var customAmount = ""
    @State private var pendingTotal = 0

    var isCustomValid: Bool {
        (Int(customAmount) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        L10nText("Add Buy-In")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        L10nText("Tap a common denomination or enter a custom amount.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(quickBuyIns, id: \.self) { amt in
                            Button {
                                pendingTotal += amt
                            } label: {
                                Text("\(settingsStore.currencySymbol)\(amt)")
                                    .font(.headline.bold())
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(Color.green)
                                    .foregroundColor(.black)
                                    .cornerRadius(14)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        NumericEntryWithDialPad(
                            placeholder: "Custom amount",
                            text: $customAmount,
                            dialPadNavigationTitle: "Buy-In"
                        )
                        Button {
                            if let a = Int(customAmount), a > 0 {
                                pendingTotal += a
                                customAmount = ""
                            }
                        } label: {
                            Group {
                                if let a = Int(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)), a > 0 {
                                    Text(
                                        "Add \(settingsStore.currencySymbol)\(a.formatted(.number.grouping(.automatic))) to total"
                                    )
                                } else {
                                    L10nText("Add Custom Amount to Total")
                                }
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCustomValid ? Color.green : Color.gray)
                            .foregroundColor(isCustomValid ? .black : .white)
                            .cornerRadius(14)
                        }
                        .disabled(!isCustomValid)

                        VStack(spacing: 6) {
                            Text(pendingTotal > 0 ? "Current buy-in total: \(settingsStore.currencySymbol)\(pendingTotal)" : "Tap amounts to build a buy-in, then confirm.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)

                            Button {
                                guard pendingTotal > 0 else { return }
                                settingsStore.lastAddOnBuyInAmount = pendingTotal
                                onAdd(pendingTotal)
                                if settingsStore.enableCasinoFeedback {
                                    CelebrationPlayer.shared.playQuickChime()
                                }
                                dismiss()
                            } label: {
                                Text(pendingTotal > 0 ? "Add \(settingsStore.currencySymbol)\(pendingTotal)" : "Add Buy-In")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(pendingTotal > 0 ? Color.green : Color.gray)
                                    .foregroundColor(pendingTotal > 0 ? .black : .white)
                                    .cornerRadius(14)
                            }
                            .disabled(pendingTotal == 0)

                            Button("Clear") {
                                pendingTotal = 0
                                customAmount = ""
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(.top, 4)

                            if let onAddFreePlay {
                                Button {
                                    dismiss()
                                    onAddFreePlay()
                                } label: {
                                    LocalizedLabel(title: "Add Free Play instead", systemImage: "ticket.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundColor(.green)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .localizedNavigationTitle("Buy-In")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
        }
        .onAppear {
            if settingsStore.lastAddOnBuyInAmount > 0 {
                pendingTotal = settingsStore.lastAddOnBuyInAmount
            }
        }
    }
}

// MARK: - Free Play Sheet

struct FreePlayQuickAddSheet: View {
    let existingSessionFreePlayTotal: Int
    let onAdd: (Int, String, Data?, Set<SessionPhotoContextTag>, [String]) -> Void
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var amountText = ""
    @State private var playTypeText = ""
    @State private var showAmountGrid = false
    @State private var freePlayPhoto: UIImage?

    private enum FreePlayPhotoSource: Identifiable {
        case camera
        case photoLibrary
        var id: Int { hashValue }
    }

    @State private var freePlayPhotoSource: FreePlayPhotoSource?
    @State private var showFreePlayPhotoOptions = false
    @State private var freePlayPhotoContextTags: Set<SessionPhotoContextTag> = []
    @State private var freePlayPhotoCustomContextLabels: [String] = []

    private var parsedAmount: Int {
        max(0, Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    private var canSubmit: Bool { parsedAmount > 0 }

    private var totalAfterAdd: Int { existingSessionFreePlayTotal + parsedAmount }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            L10nText("Add Free Play")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text("Not counted in win/loss, session ROI, or tax.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            Text("\(settingsStore.currencySymbol)\(parsedAmount.formatted(.number.grouping(.automatic)))")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(parsedAmount > 0 ? Color.green : Color.gray.opacity(0.85))
                        }
                        .padding(.top, 8)

                        if let img = freePlayPhoto {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(12)
                                .overlay(alignment: .bottomTrailing) {
                                    Button(role: .destructive) { freePlayPhoto = nil } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(7)
                                            .background(Circle().fill(Color.red.opacity(0.92)))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -4, y: -4)
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            L10nText("Type of free play")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            TextField("e.g. match play, promo credit…", text: $playTypeText)
                                .textFieldStyle(DarkTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            L10nText("Amount")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            HStack(alignment: .top, spacing: 12) {
                                Button { showAmountGrid = true } label: {
                                    HStack {
                                        Image(systemName: "square.grid.2x2.fill")
                                        Text(
                                            parsedAmount > 0
                                                ? "\(settingsStore.currencySymbol)\(parsedAmount)"
                                                : "Chip grid"
                                        )
                                        .lineLimit(1)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                NumericEntryWithDialPad(
                                    placeholder: "Exact amount",
                                    text: $amountText,
                                    dialPadNavigationTitle: "Free Play"
                                )
                                .environmentObject(settingsStore)
                            }
                        }

                        VStack(spacing: 6) {
                            if existingSessionFreePlayTotal > 0 {
                                Text("Session free play: \(settingsStore.currencySymbol)\(existingSessionFreePlayTotal.formatted(.number.grouping(.automatic)))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Text(parsedAmount > 0
                                 ? "After this entry: \(settingsStore.currencySymbol)\(totalAfterAdd.formatted(.number.grouping(.automatic)))"
                                 : "Set an amount to add free play.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)

                            Button {
                                guard canSubmit else { return }
                                let type = playTypeText.trimmingCharacters(in: .whitespacesAndNewlines)
                                onAdd(
                                    parsedAmount,
                                    type,
                                    freePlayPhoto?.jpegData(compressionQuality: 0.9),
                                    freePlayPhotoContextTags,
                                    freePlayPhotoCustomContextLabels
                                )
                                if settingsStore.enableCasinoFeedback {
                                    CelebrationPlayer.shared.playQuickChime()
                                }
                                dismiss()
                            } label: {
                                Text(canSubmit ? "Add \(settingsStore.currencySymbol)\(parsedAmount)" : "Add Free Play")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(canSubmit ? Color.green : Color.gray)
                                    .foregroundColor(canSubmit ? .black : .white)
                                    .cornerRadius(14)
                            }
                            .disabled(!canSubmit)

                            Button("Clear") {
                                amountText = ""
                                playTypeText = ""
                                freePlayPhoto = nil
                                freePlayPhotoContextTags = []
                                freePlayPhotoCustomContextLabels = []
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .padding(.bottom, 72)
                }

                Button { showFreePlayPhotoOptions = true } label: {
                    LocalizedLabel(title: "Add Photo", systemImage: "camera.viewfinder")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 5)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
            .localizedNavigationTitle("Free Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showAmountGrid) {
                BuyInGridSheet(
                    amounts: settingsStore.buyInGridAmounts,
                    selected: $amountText,
                    mode: .freePlay
                )
                .environmentObject(settingsStore)
                .presentationDetents([.fraction(0.7), .large])
                .presentationDragIndicator(.visible)
            }
            .adaptiveSheet(isPresented: $showFreePlayPhotoOptions) {
                freePlayPhotoOptionsSheet
            }
            .adaptiveSheet(item: $freePlayPhotoSource) { source in
                switch source {
                case .camera:
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        freePlayPhoto = image
                        freePlayPhotoSource = nil
                    }
                case .photoLibrary:
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        freePlayPhoto = image
                        freePlayPhotoSource = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var freePlayPhotoOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Free play photo")
                .font(.headline)
                .foregroundColor(.white)
            Text("Saved with your session photos.")
                .font(.caption)
                .foregroundColor(.gray)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showFreePlayPhotoOptions = false
                    freePlayPhotoSource = .camera
                } label: {
                    LocalizedLabel(title: "Take photo", systemImage: "camera")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            Button {
                showFreePlayPhotoOptions = false
                freePlayPhotoSource = .photoLibrary
            } label: {
                LocalizedLabel(title: "Choose from library", systemImage: "photo")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            SessionPhotoContextTagPicker(
                selectedTags: $freePlayPhotoContextTags,
                customLabels: $freePlayPhotoCustomContextLabels
            )

            Button("Cancel", role: .cancel) { showFreePlayPhotoOptions = false }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(settingsStore.primaryGradient)
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
    }
}

/// Enter current chip stack while live; session win/loss vs buy-ins and $/hr update until close-out.
struct UpdateStackSheet: View {
    let sessionID: UUID
    let game: String
    let casino: String
    /// Cash buy-in plus free play — stack preview baseline.
    let stackBaseline: Int
    let currentTrackedStack: Int?
    let hoursPlayed: Double
    let onUpdate: (Int) -> Void
    var onAddFreePlay: (() -> Void)? = nil
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var pendingStack = 0
    @State private var customAmount = ""
    @State private var showBuyInGrid = false
    @State private var gridAmountScratch = ""
    @State private var stackWinConfettiBurst = 0
    @State private var showChipEstimatorSheet = false
    @State private var chipEstimatorError: String?
    @State private var showSubscriptionPaywall = false

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private var isCustomValid: Bool {
        (Int(customAmount) ?? 0) > 0
    }

    private var previewWinLoss: Int {
        pendingStack - stackBaseline
    }

    private var previewRatePerHour: Double? {
        let wl = previewWinLoss
        guard hoursPlayed > 1e-6 else { return nil }
        return Double(wl) / hoursPlayed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        L10nText("Update Stack")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Table result is stack minus buy-in and free play (\(settingsStore.currencySymbol)\(stackBaseline.formatted(.number.grouping(.automatic))) total). Cash win/loss at close-out uses buy-in only.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Button {
                        gridAmountScratch = ""
                        showBuyInGrid = true
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.2x2.fill")
                            Text(
                                pendingStack > 0
                                    ? "\(settingsStore.currencySymbol)\(pendingStack.formatted(.number.grouping(.automatic))) — chip grid"
                                    : "Choose stack on chip grid"
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6).opacity(0.25))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    VStack(spacing: 12) {
                        NumericEntryWithDialPad(
                            placeholder: "Custom amount",
                            text: $customAmount,
                            dialPadNavigationTitle: "Stack"
                        )
                        Button {
                            if let a = Int(customAmount), a > 0 {
                                pendingStack += a
                                customAmount = ""
                            }
                        } label: {
                            Group {
                                if let a = Int(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)), a > 0 {
                                    Text(
                                        "Add \(settingsStore.currencySymbol)\(a.formatted(.number.grouping(.automatic))) to stack"
                                    )
                                } else {
                                    Text("Add custom amount to stack")
                                }
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCustomValid ? Color.green : Color.gray)
                            .foregroundColor(isCustomValid ? .black : .white)
                            .cornerRadius(14)
                        }
                        .disabled(!isCustomValid)

                        VStack(spacing: 10) {
                            Text("Stack total: \(settingsStore.currencySymbol)\(pendingStack.formatted(.number.grouping(.automatic)))")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)

                            VStack(spacing: 6) {
                                Text("Session (vs buy-in)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(formatSignedCurrency(previewWinLoss))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(previewWinLoss >= 0 ? .green : .red)
                                if let rate = previewRatePerHour {
                                    Text(formatRatePerHour(rate))
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }

                            Button {
                                let showConfetti = previewWinLoss > 0 && !accessibilityReduceMotion
                                onUpdate(pendingStack)
                                if settingsStore.enableCasinoFeedback {
                                    CelebrationPlayer.shared.playQuickChime()
                                }
                                if showConfetti {
                                    stackWinConfettiBurst += 1
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 950_000_000)
                                        dismiss()
                                    }
                                } else {
                                    dismiss()
                                }
                            } label: {
                                L10nText("Update Stack")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.black)
                                    .cornerRadius(14)
                            }

                            Button("Clear") {
                                pendingStack = 0
                                customAmount = ""
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(.top, 4)

                            if let onAddFreePlay {
                                Button {
                                    dismiss()
                                    onAddFreePlay()
                                } label: {
                                    LocalizedLabel(title: "Add Free Play", systemImage: "ticket.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundColor(.green)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding()

                StackWinConfettiBurst(burstID: stackWinConfettiBurst, enabled: !accessibilityReduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            if settingsStore.requiresTierTapAIFeaturePaywall(
                                isSignedIn: authStore.isSignedIn,
                                hasProAccess: hasProAccess
                            ) {
                                showSubscriptionPaywall = true
                            } else {
                                startChipEstimatorFlow()
                            }
                        } label: {
                            LocalizedLabel(title: "Chip Estimator", systemImage: "camera.viewfinder")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 5)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
                .allowsHitTesting(true)
            }
            .localizedNavigationTitle("Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showBuyInGrid) {
                BuyInGridSheet(
                    amounts: settingsStore.buyInGridAmounts,
                    selected: $gridAmountScratch,
                    mode: .stackAmount
                )
                .environmentObject(settingsStore)
                .presentationDetents([.fraction(0.7), .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: gridAmountScratch) { newVal in
                if let v = Int(newVal), v > 0 {
                    pendingStack = v
                }
            }
            .alert("Chip estimator error", isPresented: Binding<Bool>(
                get: { chipEstimatorError != nil },
                set: { if !$0 { chipEstimatorError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chipEstimatorError ?? "Something went wrong while estimating the chip value.")
            }
            .adaptiveSheet(isPresented: $showChipEstimatorSheet) {
                ChipEstimatorSheetView(
                    sessionID: sessionID,
                    game: game,
                    casino: casino,
                    applyMode: .liveStack($pendingStack)
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
                .environment(\.appLanguage, settingsStore.appLanguage)
            }
            .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
        }
        .onAppear {
            pendingStack = max(0, currentTrackedStack ?? stackBaseline)
        }
    }

    private func startChipEstimatorFlow() {
        guard SupabaseConfig.isConfigured else {
            chipEstimatorError = "AI is not configured for this build."
            return
        }
        if settingsStore.requiresTierTapAIFeaturePaywall(
            isSignedIn: authStore.isSignedIn,
            hasProAccess: subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
        ) {
            showSubscriptionPaywall = true
            return
        }
        showChipEstimatorSheet = true
    }

    private func formatSignedCurrency(_ value: Int) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return "\(sign)\(settingsStore.currencySymbol)\(abs(value).formatted(.number.grouping(.automatic)))"
    }

    private func formatRatePerHour(_ rate: Double) -> String {
        let rounded = rate.rounded()
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "-" : "")
        let mag = abs(rounded)
        return "\(sign)\(settingsStore.currencySymbol)\(Int(mag).formatted(.number.grouping(.automatic)))/hr"
    }
}

// MARK: - Live Comp Sheet

/// Thumbnail for a comp receipt stored on disk (`CompPhotoStorage`); not part of session JSON.
struct CompEventPhotoThumbnail: View {
    let compEventID: UUID
    var side: CGFloat = 44
    /// When true (e.g. trip share card), shows a gift icon if no JPEG is on disk so rows still align.
    var showPlaceholderWhenMissing: Bool = false

    var body: some View {
        Group {
            if let url = CompPhotoStorage.url(for: compEventID),
               FileManager.default.fileExists(atPath: url.path),
               let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                    .cornerRadius(8)
            } else if showPlaceholderWhenMissing {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                    Image(systemName: "gift.fill")
                        .font(.system(size: max(12, side * 0.32)))
                        .foregroundColor(.white.opacity(0.45))
                }
                .frame(width: side, height: side)
            }
        }
    }
}

/// Review AI-suggested food & beverage comp value before applying to the form.
private struct CompEstimateReviewSheet: View {
    let currencySymbol: String
    let dollars: Int
    /// Explanation of how the model arrived at the amount (shown under the TierTap headline).
    let reason: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    private var estimateLine: String {
        let amt = dollars.formatted(.number.grouping(.automatic))
        return "TierTap AI estimates this comp at \(currencySymbol)\(amt)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [settingsStore.secondaryColor, settingsStore.primaryColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(estimateLine)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            L10nText("Why this amount")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            Text(reason)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)

                            L10nText("Accept fills Est. value. Details only adds a short note that TierTap AI performed the estimate—not the explanation above.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    HStack(spacing: 12) {
                        Button(action: onDecline) {
                            L10nText("Decline")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.white.opacity(0.22))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: onAccept) {
                            L10nText("Accept")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .background(Color.black.opacity(0.12))
                }
            }
            .localizedNavigationTitle("Comp estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(
                    colors: [settingsStore.secondaryColor, settingsStore.primaryColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.fraction(0.55), .medium])
        .presentationDragIndicator(.visible)
    }
}

struct CompQuickAddSheet: View {
    /// Sum of comp amounts already recorded for this session (running total before this entry).
    let existingSessionCompTotal: Int
    /// Sum of free play already logged (for dollars/credits “free play comp” toggle).
    var existingSessionFreePlayTotal: Int = 0
    /// Live session table game (for AI comp value estimation).
    var sessionGame: String = ""
    /// Live session casino / location name (for AI comp value estimation).
    var sessionCasino: String = ""
    /// WGS84 coordinates from check-in map pick, when available (for regional pricing context).
    var sessionCasinoLatitude: Double? = nil
    var sessionCasinoLongitude: Double? = nil
    /// Last parameter is true when dollars/credits should be stored as free play (not a comp).
    let onAdd: (CompKind, Int, String?, FoodBeverageKind?, String?, Data?, Bool) -> Void
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedKind: CompKind = .foodBeverage
    /// Dollars / credits comp value (same grid + exact field pattern as buy-in).
    @State private var dollarsCreditsText = ""
    @State private var dollarsCreditsIsFreePlay = false
    @State private var showDollarsCreditsGrid = false
    @State private var foodValueText = ""
    @State private var foodBeverageKind: FoodBeverageKind = .meal
    @State private var detailsText = ""
    @State private var foodBeverageOtherText = ""
    @State private var compPhoto: UIImage?

    private enum CompPhotoSource: Identifiable {
        case camera
        case photoLibrary

        var id: Int { hashValue }
    }

    @State private var compPhotoSource: CompPhotoSource?
    @State private var showCompPhotoOptions = false

    @State private var showSubscriptionPaywall = false
    @State private var isEstimatingCompValue = false
    @State private var compEstimatorError: String?
    @State private var pendingCompEstimate: PendingCompEstimate?

    private struct PendingCompEstimate: Identifiable {
        let id = UUID()
        let dollars: Int
        let reason: String
    }

    /// Matches Est. value `TextField` + spacing + Estimator button on the food row (below the column labels).
    private static let compDetailsEditorHeight: CGFloat = 100
    /// Minimum height so an empty details field shows ~3 caption lines.
    private static var compDetailsTextFieldMinHeight: CGFloat {
        let line = UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        return line * 3 + 8
    }

    private var dollarsCreditsValue: Int {
        max(0, Int(dollarsCreditsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    private var parsedFoodValue: Int {
        Int(foodValueText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var parsedValueForSubmit: Int {
        switch selectedKind {
        case .dollarsCredits: return dollarsCreditsValue
        case .foodBeverage: return parsedFoodValue
        }
    }

    private var canSubmit: Bool {
        parsedValueForSubmit > 0
    }

    private var totalAfterAdd: Int {
        if selectedKind == .dollarsCredits && dollarsCreditsIsFreePlay {
            return existingSessionFreePlayTotal + parsedValueForSubmit
        }
        return existingSessionCompTotal + parsedValueForSubmit
    }

    @ViewBuilder
    private func detailsOptionalEditorField() -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            TextField("e.g. host name, promo…", text: $detailsText, axis: .vertical)
                .font(.caption)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .textFieldStyle(DarkTextFieldStyle())
                .frame(maxWidth: .infinity, minHeight: Self.compDetailsTextFieldMinHeight, alignment: .topLeading)
        }
        .frame(height: Self.compDetailsEditorHeight)
    }

    private var sessionCompTotalsFooter: some View {
        VStack(spacing: 4) {
            if existingSessionCompTotal > 0 {
                Text("All comps: \(settingsStore.currencySymbol)\(existingSessionCompTotal.formatted(.number.grouping(.automatic)))")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            Text(parsedValueForSubmit > 0
                 ? (selectedKind == .dollarsCredits && dollarsCreditsIsFreePlay
                    ? "After this entry, session free play total: \(settingsStore.currencySymbol)\(totalAfterAdd.formatted(.number.grouping(.automatic)))"
                    : "After this entry, session comps total: \(settingsStore.currencySymbol)\(totalAfterAdd.formatted(.number.grouping(.automatic)))")
                 : "Set a value to see the new total.")
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var addCompSubmitButton: some View {
        Button {
            guard parsedValueForSubmit > 0 else { return }
            let kind = selectedKind
            let note = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fb: FoodBeverageKind? = (kind == .foodBeverage) ? foodBeverageKind : nil
            let otherTrim = foodBeverageOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
            let otherDesc: String? = (kind == .foodBeverage && fb == .other && !otherTrim.isEmpty) ? otherTrim : nil
            if kind == .foodBeverage {
                settingsStore.lastFoodBeverageCompKind = foodBeverageKind
            }
            let asFreePlay = (kind == .dollarsCredits && dollarsCreditsIsFreePlay)
            onAdd(kind, parsedValueForSubmit, note.isEmpty ? nil : note, fb, otherDesc, compPhoto?.jpegData(compressionQuality: 0.9), asFreePlay)
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.playQuickChime()
            }
            dismiss()
        } label: {
            Text(canSubmit
                 ? (selectedKind == .dollarsCredits && dollarsCreditsIsFreePlay
                    ? "Add \(settingsStore.currencySymbol)\(parsedValueForSubmit) free play"
                    : "Add \(settingsStore.currencySymbol)\(parsedValueForSubmit)")
                 : (selectedKind == .dollarsCredits && dollarsCreditsIsFreePlay ? "Add free play" : "Add comp"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSubmit ? Color.green : Color.gray)
                .foregroundColor(canSubmit ? .black : .white)
                .cornerRadius(14)
        }
        .disabled(!canSubmit)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(spacing: 10) {
                                L10nText("Add Comp")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text("\(settingsStore.currencySymbol)\(parsedValueForSubmit.formatted(.number.grouping(.automatic)))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(parsedValueForSubmit > 0 ? Color.green : Color.gray.opacity(0.85))
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)

                            if let img = compPhoto {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipped()
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.green.opacity(0.5), lineWidth: 1)
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        Button(role: .destructive) {
                                            compPhoto = nil
                                        } label: {
                                            Image(systemName: "trash.fill")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(7)
                                                .background(Circle().fill(Color.red.opacity(0.92)))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: -4, y: -4)
                                    }
                            }
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            L10nText("Comp type")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gray)
                            HStack(spacing: 12) {
                                compTypeButton(.dollarsCredits)
                                compTypeButton(.foodBeverage)
                            }
                        }

                        if selectedKind == .dollarsCredits {
                            dollarsCreditsBuyInStyleSection
                            Toggle(isOn: $dollarsCreditsIsFreePlay) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("This is free play")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text("Stored with free play (not comps) so totals are not double-counted.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(.green)
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    L10nText("Details (optional)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.gray)
                                    detailsOptionalEditorField()
                                }
                                addCompSubmitButton
                                    .padding(.top, 6)
                                sessionCompTotalsFooter
                                    .padding(.top, 6)
                            }
                        } else if selectedKind == .foodBeverage {
                            foodBeverageSection
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    L10nText("Details (optional)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.gray)
                                    detailsOptionalEditorField()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Est. value (\(settingsStore.currencySymbol))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.gray)
                                    NumericEntryWithDialPad(
                                        placeholder: "0",
                                        text: $foodValueText,
                                        dialPadNavigationTitle: "Amount"
                                    )
                                    Button {
                                        if authStore.isSignedIn {
                                            if settingsStore.requiresTierTapAIFeaturePaywall(
                                                isSignedIn: true,
                                                hasProAccess: subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
                                            ) {
                                                showSubscriptionPaywall = true
                                            } else {
                                                Task { await runCompValueEstimator() }
                                            }
                                        } else {
                                            showSubscriptionPaywall = true
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                            L10nText("Estimator")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .minimumScaleFactor(0.85)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 4)
                                        .background(Color.black.opacity(0.9))
                                        .foregroundColor(.green)
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isEstimatingCompValue)
                                }
                                .frame(minWidth: 132, maxWidth: 180, alignment: .leading)
                            }
                            sessionCompTotalsFooter
                            addCompSubmitButton
                        }

                        Button("Clear") {
                            dollarsCreditsText = ""
                            dollarsCreditsIsFreePlay = false
                            foodValueText = ""
                            foodBeverageOtherText = ""
                            foodBeverageKind = settingsStore.lastFoodBeverageCompKind
                            detailsText = ""
                            compPhoto = nil
                            selectedKind = .foodBeverage
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                    .padding()
                    .padding(.bottom, 72)
                }
                Button {
                    showCompPhotoOptions = true
                } label: {
                    LocalizedLabel(title: "Add Photo", systemImage: "camera.viewfinder")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 5)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                if isEstimatingCompValue {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                    .scaleEffect(1.3)
                                L10nText("Estimating comp value…")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                L10nText("Getting an estimate with TierTap AI.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(20)
                            .background(Color(.systemGray6).opacity(0.95))
                            .cornerRadius(18)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .localizedNavigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.green)
                }
            }
            .adaptiveSheet(isPresented: $showCompPhotoOptions) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add comp photo")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Capture your comp slip, receipt, or screen and TierTap will attach it to this entry.")
                        .font(.caption)
                        .foregroundColor(.gray)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCompPhotoOptions = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                compPhotoSource = .camera
                            }
                        } label: {
                            LocalizedLabel(title: "Take photo", systemImage: "camera")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    Button {
                        showCompPhotoOptions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            compPhotoSource = .photoLibrary
                        }
                    } label: {
                        LocalizedLabel(title: "Choose from library", systemImage: "photo")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button("Cancel", role: .cancel) {
                        showCompPhotoOptions = false
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .padding(16)
                .background(settingsStore.primaryGradient)
                .presentationDetents([.fraction(0.33)])
                .presentationDragIndicator(.visible)
            }
            .adaptiveSheet(item: $compPhotoSource) { source in
                switch source {
                case .camera:
                    CameraPicker(selectedImage: .constant(nil)) { image in
                        compPhoto = image
                    }
                case .photoLibrary:
                    ImagePicker(selectedImage: .constant(nil)) { image in
                        compPhoto = image
                    }
                }
            }
            .alert("Comp estimator", isPresented: Binding(
                get: { compEstimatorError != nil },
                set: { if !$0 { compEstimatorError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(compEstimatorError ?? "")
            }
            .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
            .adaptiveSheet(isPresented: $showDollarsCreditsGrid) {
                BuyInGridSheet(
                    amounts: settingsStore.buyInGridAmounts,
                    selected: $dollarsCreditsText,
                    mode: .compAmount
                )
                .environmentObject(settingsStore)
            }
            .sheet(item: $pendingCompEstimate) { estimate in
                CompEstimateReviewSheet(
                    currencySymbol: settingsStore.currencySymbol,
                    dollars: estimate.dollars,
                    reason: estimate.reason,
                    onAccept: {
                        recordCompEstimatorOutcomeForQuickAdd(accepted: true)
                        foodValueText = String(estimate.dollars)
                        let aiNote = "— TierTap AI estimated this comp value."
                        if detailsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            detailsText = aiNote
                        } else {
                            detailsText = detailsText.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + aiNote
                        }
                        pendingCompEstimate = nil
                    },
                    onDecline: {
                        recordCompEstimatorOutcomeForQuickAdd(accepted: false)
                        pendingCompEstimate = nil
                    }
                )
                .environmentObject(settingsStore)
            }
        }
        .onAppear {
            foodBeverageKind = settingsStore.lastFoodBeverageCompKind
        }
    }

    private func foodBeverageDescriptionForPrompt() -> String {
        let base = foodBeverageKind.label
        if foodBeverageKind == .other {
            let o = foodBeverageOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return o.isEmpty ? base : "\(base): \(o)"
        }
        return base
    }

    private func recordCompEstimatorOutcomeForQuickAdd(accepted: Bool) {
        let casinoKey = sessionCasino.isEmpty ? "Unknown casino" : sessionCasino
        let gameKey = sessionGame.isEmpty ? "Unknown table game" : sessionGame
        CompEstimatorQualityStatsAPI.recordOutcomeBestEffort(
            casinoKey: casinoKey,
            gameKey: gameKey,
            accepted: accepted
        )
    }

    /// Builds a geographic description for the AI: prefers stored GPS from check-in; otherwise best-effort forward geocode of the casino name.
    private func geographicContextForCompEstimator(casinoName: String, latitude: Double?, longitude: Double?) async -> String {
        if let lat = latitude, let lon = longitude, lat >= -90, lat <= 90, lon >= -180, lon <= 180 {
            return "Geographic anchor (WGS84): \(String(format: "%.5f", lat)), \(String(format: "%.5f", lon)). Use this position to infer country/region, local cost-of-living, resort market tier, and typical F&B pricing for that area—do not rely on the casino name string alone."
        }
        let trimmed = casinoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No geographic coordinates or casino name; use photo and details only."
        }
        return await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(trimmed) { placemarks, _ in
                if let p = placemarks?.first, let loc = p.location {
                    let c = loc.coordinate
                    let locality = p.locality ?? ""
                    let admin = p.administrativeArea ?? ""
                    let country = p.country ?? ""
                    let parts = [locality, admin, country].filter { !$0.isEmpty }.joined(separator: ", ")
                    let coordLine = "Approx. coordinates: \(String(format: "%.4f", c.latitude)), \(String(format: "%.4f", c.longitude))."
                    let placeLine = parts.isEmpty ? "" : "Placemark: \(parts). "
                    continuation.resume(returning: "\(placeLine)\(coordLine) Use this geography for regional pricing and resort market expectations—not the venue name alone.")
                } else {
                    continuation.resume(returning: "Casino name only: \(trimmed). No coordinates resolved; infer region cautiously from the name plus photo/details.")
                }
            }
        }
    }

    private func runCompValueEstimator() async {
        let detailsTrim = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDetails = !detailsTrim.isEmpty
        let hasPhoto = compPhoto != nil

        guard hasPhoto || hasDetails else {
            await MainActor.run {
                compEstimatorError = "Add a comp photo and/or enter details, then run Estimator."
            }
            return
        }
        guard SupabaseConfig.isConfigured, let client = supabase else {
            await MainActor.run { compEstimatorError = "AI is not configured for this build." }
            return
        }
        guard authStore.isSignedIn else {
            await MainActor.run { compEstimatorError = "Comp Estimator is only available to signed-in users." }
            return
        }
        if settingsStore.requiresTierTapAIFeaturePaywall(
            isSignedIn: authStore.isSignedIn,
            hasProAccess: subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
        ) {
            await MainActor.run { showSubscriptionPaywall = true }
            return
        }

        await MainActor.run {
            isEstimatingCompValue = true
            compEstimatorError = nil
        }

        struct GeminiInlineData: Encodable {
            let mime_type: String
            let data: String
            enum CodingKeys: String, CodingKey {
                case mime_type = "mime_type"
                case data
            }
        }
        struct GeminiPartImage: Encodable {
            let text: String?
            let inline_data: GeminiInlineData?
            enum CodingKeys: String, CodingKey {
                case text
                case inline_data = "inline_data"
            }
        }
        struct GeminiContentImage: Encodable {
            let role: String
            let parts: [GeminiPartImage]
        }
        struct GeminiImageRequest: Encodable {
            let contents: [GeminiContentImage]
        }
        struct GeminiTextRequest: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable {
                let role: String
                let parts: [Part]
            }
            let contents: [Content]
        }
        struct CompEstimatePayload: Decodable {
            let estimate_dollars: Int?
            let reason: String?
        }

        var imageData: String?
        if hasPhoto, let image = compPhoto {
            imageData = image.jpegData(compressionQuality: 0.9)?.base64EncodedString()
            if imageData == nil {
                await MainActor.run {
                    isEstimatingCompValue = false
                    compEstimatorError = "Unable to process image."
                }
                return
            }
        }

        let gameText = sessionGame.trimmingCharacters(in: .whitespacesAndNewlines)
        let gameLine = gameText.isEmpty ? "Unknown table game" : gameText
        let casinoText = sessionCasino.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationLine = casinoText.isEmpty ? "Unknown casino / location" : casinoText
        let fbLine = foodBeverageDescriptionForPrompt()
        let detailsLine = hasDetails ? detailsTrim : "(none)"
        let currencyLine = "\(settingsStore.currencyCode) (\(settingsStore.currencySymbol))"
        let geographicContextLine = await geographicContextForCompEstimator(
            casinoName: casinoText,
            latitude: sessionCasinoLatitude,
            longitude: sessionCasinoLongitude
        )

        let inputMode: String
        if hasPhoto && hasDetails {
            inputMode = """
            Inputs: You have BOTH a photo and the user's written details. Combine them: prefer concrete evidence from the image when it conflicts with vague text; use details for context the photo does not show.
            """
        } else if hasPhoto {
            inputMode = """
            Inputs: You have a photo only (no separate written comp description). Use the image as primary evidence: menu, receipt, plated food, drinks, room service ticket, comp slip, or similar.
            """
        } else {
            inputMode = """
            Inputs: There is NO photo. Estimate a typical fair retail / cash-equivalent value from the user's written description of what they received or were comped, combined with the casino location and session context. Use reasonable assumptions for that market and property tier.
            """
        }

        let prompt = """
        Estimate the fair retail / cash-equivalent value (typical average for this kind of comp) for a casino food & beverage comp.

        \(inputMode)

        Session context:
        - Casino / location (display name): \(locationLine)
        - Geography (use for regional cost levels, not just the name above): \(geographicContextLine)
        - Table game: \(gameLine)
        - Comp category: \(fbLine)
        - User-entered comp details: \(detailsLine)
        - User's currency for amounts: \(currencyLine)

        Anchor your dollar estimate to the geography (coordinates / placemark) when provided: same venue name can mean different markets (e.g. Las Vegas Strip vs regional locals vs international). Weight local F&B and resort pricing for that region.

        If you cannot form a reasonable estimate from the inputs, set estimate_dollars to null and explain in reason.

        Respond with ONLY valid JSON (no markdown fences), exactly this shape:
        {"estimate_dollars": <integer or null>, "reason": "<string>"}
        The integer must be a whole number in the user's currency (same unit as their bankroll in the app).
        If estimate_dollars is null: reason must be a short sentence explaining why.
        If estimate_dollars is set: reason must be non-empty and give a clear, detailed explanation (about 2–5 short sentences) of how you chose that amount—geography/market, what you saw in the photo or details, and typical retail for that comp type. Do not start reason with "TierTap"; the app adds its own headline.
        """

        do {
            if !subscriptionStore.isPro && !settingsStore.isSubscriptionOverrideActive {
                await MainActor.run { settingsStore.registerAICall() }
            }

            let response: GeminiRouterAPIResponse
            if let imgData = imageData {
                let inner = GeminiImageRequest(
                    contents: [
                        .init(
                            role: "user",
                            parts: [
                                .init(text: prompt, inline_data: nil),
                                .init(
                                    text: nil,
                                    inline_data: GeminiInlineData(
                                        mime_type: "image/jpeg",
                                        data: imgData
                                    )
                                )
                            ]
                        )
                    ]
                )
                let routerBody = GeminiProxyBody(contents: inner.contents, language: settingsStore.appLanguage)
                response = try await GeminiRouterThrottle.shared.executeWithRetries {
                    try await client.functions.invoke(
                        "gemini-router",
                        options: FunctionInvokeOptions(body: routerBody)
                    )
                }
            } else {
                let inner = GeminiTextRequest(
                    contents: [
                        .init(role: "user", parts: [.init(text: prompt)])
                    ]
                )
                let routerBody = GeminiProxyBody(contents: inner.contents, language: settingsStore.appLanguage)
                response = try await GeminiRouterThrottle.shared.executeWithRetries {
                    try await client.functions.invoke(
                        "gemini-router",
                        options: FunctionInvokeOptions(body: routerBody)
                    )
                }
            }
            await MainActor.run {
                settingsStore.recordAITelemetry(
                    invocationTokens: response.telemetryTokenTotal,
                    hasProAccess: subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
                )
            }
            let text = response.candidates?
                .first?
                .content?
                .parts?
                .compactMap { $0.text }
                .joined(separator: "\n") ?? ""

            let jsonText = Self.extractJSONObject(from: text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = Data(jsonText.utf8)
            let payload = try JSONDecoder().decode(CompEstimatePayload.self, from: data)

            await MainActor.run {
                isEstimatingCompValue = false
            }

            guard let dollars = payload.estimate_dollars, dollars > 0 else {
                let msg = payload.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                await MainActor.run {
                    compEstimatorError = msg.isEmpty ? "TierTap could not estimate a value from this input." : msg
                }
                return
            }
            let rawReason = payload.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detailReason = rawReason.isEmpty
                ? "This amount reflects typical retail for this comp type given your region, venue tier, and what you shared in the photo or details."
                : rawReason
            await MainActor.run {
                pendingCompEstimate = PendingCompEstimate(dollars: dollars, reason: detailReason)
            }
        } catch {
            await MainActor.run {
                isEstimatingCompValue = false
                compEstimatorError = error.localizedDescription
            }
        }
    }

    private static func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        return String(trimmed[start ... end])
    }

    /// Same pattern as check-in / past-session buy-in: chip grid sheet + exact amount + dial pad.
    private var dollarsCreditsBuyInStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedLabel(title: "Comp amount", systemImage: "dollarsign.circle")
                .font(.headline)
                .foregroundColor(.white)
            HStack(alignment: .top, spacing: 12) {
                Button { showDollarsCreditsGrid = true } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2.fill")
                        Text(dollarsCreditsText.isEmpty ? "Choose cash" : "\(settingsStore.currencySymbol)\(dollarsCreditsText)")
                            .lineLimit(1)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    NumericEntryWithDialPad(
                        placeholder: "Exact amount",
                        text: $dollarsCreditsText,
                        dialPadNavigationTitle: "Buy-In"
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var foodBeverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            L10nText("Type")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gray)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(FoodBeverageKind.allCases.filter { $0 != .other }, id: \.self) { fb in
                    Button {
                        foodBeverageKind = fb
                        foodBeverageOtherText = ""
                        settingsStore.lastFoodBeverageCompKind = fb
                    } label: {
                        Text(fb.label)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 6)
                            .background(foodBeverageKind == fb ? Color.green.opacity(0.85) : Color(.systemGray6).opacity(0.35))
                            .foregroundColor(foodBeverageKind == fb ? .black : .white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(foodBeverageKind == fb ? Color.green : Color.gray.opacity(0.4), lineWidth: foodBeverageKind == fb ? 2 : 1)
                            )
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(alignment: .center, spacing: 10) {
                Button {
                    foodBeverageKind = .other
                    settingsStore.lastFoodBeverageCompKind = .other
                } label: {
                    Text(FoodBeverageKind.other.label)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background(foodBeverageKind == .other ? Color.green.opacity(0.85) : Color(.systemGray6).opacity(0.35))
                        .foregroundColor(foodBeverageKind == .other ? .black : .white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(foodBeverageKind == .other ? Color.green : Color.gray.opacity(0.4), lineWidth: foodBeverageKind == .other ? 2 : 1)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                TextField("Comp type (e.g. buffet)", text: $foodBeverageOtherText)
                    .textFieldStyle(DarkTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .onChange(of: foodBeverageOtherText) { new in
                        let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        if foodBeverageKind != .other {
                            foodBeverageKind = .other
                            settingsStore.lastFoodBeverageCompKind = .other
                        }
                    }
            }
        }
    }

    private func compTypeButton(_ kind: CompKind) -> some View {
        let isOn = selectedKind == kind
        return Button {
            selectedKind = kind
            if kind != .dollarsCredits {
                dollarsCreditsIsFreePlay = false
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .font(.title)
                Text(kind.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Text(kind.subtitle)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(12)
            .background(isOn ? Color.green.opacity(0.35) : Color(.systemGray6).opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOn ? Color.green : Color.clear, lineWidth: 2)
            )
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Celebration & Confetti

final class CelebrationPlayer {
    static let shared = CelebrationPlayer()
    private var player: AVAudioPlayer?

    func celebrateWin() {
        triggerHaptics()
        playSound(for: .bigWin)
    }

    /// Generic casino-style chime + success haptics for key button events.
    func playQuickChime() {
        triggerHaptics()
        playSound(for: .quickChime)
    }

    /// Slot-machine coin sound used when wallet tier points change.
    func playTierChangeCoins() {
        triggerHaptics()
        playSound(for: .tierChangeCoins)
    }

    private func triggerHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// High-level sound events we care about. Each profile can map these to different files.
    private enum Event {
        case quickChime
        case bigWin
        case tierChangeCoins
    }

    private func currentProfile() -> SettingsStore.SoundProfile {
        let stored = UserDefaults.standard.string(forKey: "ctt_sound_profile")
        return SettingsStore.SoundProfile(rawValue: stored ?? "") ?? .classicCasino
    }

    private func playSound(for event: Event) {
        let profile = currentProfile()
        let fileName: String

        switch (profile, event) {
        case (.classicCasino, .quickChime):
            fileName = "coins_clinking"
        case (.softChimes, .quickChime):
            fileName = "cat_star_collect"
        case (.arcadeLights, .quickChime):
            fileName = "boodoodaloop"

        case (_, .bigWin):
            fileName = "victory_confetti"
        case (_, .tierChangeCoins):
            fileName = "coins_clinking"
        }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
            print("⚠️ [CelebrationPlayer] Missing sound in bundle:", fileName, "for profile:", profile.rawValue, "event:", event)
            return
        }
        print("✅ [CelebrationPlayer] Playing sound:", fileName, "for profile:", profile.rawValue, "event:", event, "url:", url)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}

private enum ConfettiPieceKind {
    case color(Color)
    case emoji(String)
}

private let confettiColors: [Color] = [.green, .yellow, .orange, .pink, .purple]
private let confettiEmojis = ["🎲", "♠️", "♥️", "♦️", "♣️", "🪙", "💰", "💵", "💴", "💶", "💷", "💸"]
private let confettiPieceKinds: [ConfettiPieceKind] = {
    confettiColors.map { ConfettiPieceKind.color($0) } +
    confettiEmojis.map { ConfettiPieceKind.emoji($0) }
}()

struct ConfettiCelebrationView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    private let pieceCount = 80

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieceCount, id: \.self) { index in
                    ConfettiPiece(
                        index: index,
                        containerSize: geo.size,
                        kind: confettiPieceKinds[abs(index.hashValue) % confettiPieceKinds.count]
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            if settingsStore.enableCasinoFeedback {
                CelebrationPlayer.shared.celebrateWin()
            }
        }
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let containerSize: CGSize
    let kind: ConfettiPieceKind
    @State private var yOffset: CGFloat = -200
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0

    var body: some View {
        let size = CGFloat(8 + (index % 11))
        Group {
            switch kind {
            case .color(let color):
                RoundedRectangle(cornerRadius: size / 3)
                    .fill(color)
                    .frame(width: size, height: size * 1.6)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: size * 2.2))
            }
        }
        .rotationEffect(.degrees(rotation))
        .offset(x: xOffset, y: yOffset)
        .onAppear {
            let halfW = containerSize.width / 2
            let halfH = containerSize.height / 2
            xOffset = CGFloat.random(in: -halfW...halfW)
            yOffset = -halfH - CGFloat.random(in: 80...280)
            let endY = halfH + CGFloat.random(in: 80...200)
            let delay = Double(index) * 0.012
            withAnimation(.easeOut(duration: 2.2).delay(delay)) {
                yOffset = endY
            }
            withAnimation(.linear(duration: 2.2).delay(delay)) {
                rotation = Double.random(in: 180...720)
            }
        }
    }
}

#if os(iOS)
extension UIImage {
    /// Returns a copy with black/near-black pixels made transparent so the background shows through.
    func withBlackPixelsMadeTransparent(threshold: UInt8 = 40) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                if r <= threshold && g <= threshold && b <= threshold {
                    buffer[offset] = 0
                    buffer[offset + 1] = 0
                    buffer[offset + 2] = 0
                    buffer[offset + 3] = 0
                }
            }
        }

        guard let outCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outCGImage, scale: scale, orientation: imageOrientation)
    }

    /// Returns a copy with the TierTap logo in the bottom-right (same layout as session-art AI shares).
    func withTierTapShareLogoOverlay() -> UIImage {
        guard let logo = UIImage(named: "TierTapLogo") else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
            let minSide = min(size.width, size.height)
            let logoWidth = max(72, minSide * 0.16)
            let ratio = logo.size.height > 0 ? (logo.size.width / logo.size.height) : 1
            let logoHeight = logoWidth / max(ratio, 0.001)
            let pad = max(18, minSide * 0.03)
            let rect = CGRect(
                x: size.width - logoWidth - pad,
                y: size.height - logoHeight - pad,
                width: logoWidth,
                height: logoHeight
            )
            logo.draw(in: rect, blendMode: .normal, alpha: 0.95)
        }
    }
}

enum TransparentLogoCache {
    static var image: UIImage? = {
        UIImage(named: "LogoSplash")?.withBlackPixelsMadeTransparent()
    }()
}
#endif
