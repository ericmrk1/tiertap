import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemGray6).opacity(0.25))
            .foregroundColor(.white)
            .cornerRadius(10)
            .tint(.green)
    }
}

struct GameButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 4)
                .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(10)
        }
    }
}

struct InputRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold()).foregroundColor(.white)
            TextField(placeholder, text: $value)
                .textFieldStyle(DarkTextFieldStyle())
                .keyboardType(.numberPad)
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

struct GamePickerView: View {
    @Binding var selectedGame: String
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    @State private var dynamicGames: [String] = []
    @State private var isLoading = false

    private var favorites: [String] { settingsStore.favoriteGames }

    private var allGamesUnion: [String] {
        let hardCoded = GamesList.all
        let combined = Set(hardCoded + dynamicGames)
        return Array(combined).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                List {
                    if isLoading {
                        ProgressView("Loading games…")
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                    }
                    if !filteredFavorites.isEmpty {
                        Section("Favorites") {
                            ForEach(filteredFavorites, id: \.self) { game in
                                gameRow(game)
                            }
                        }
                    }
                    Section(filteredFavorites.isEmpty ? "Games" : "All games") {
                        ForEach(filteredOthers, id: \.self) { game in
                            gameRow(game)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            .searchable(text: $search, prompt: "Search games")
            .navigationTitle("Select Game").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .task {
                await loadDynamicGames()
            }
        }
    }
    private func gameRow(_ game: String) -> some View {
        Button {
            selectedGame = game
            dismiss()
        } label: {
            HStack {
                Text(game).foregroundColor(.white)
                Spacer()
                if selectedGame == game { Image(systemName: "checkmark").foregroundColor(.green) }
            }
        }
        .listRowBackground(Color(.systemGray6).opacity(0.15))
    }

    private func loadDynamicGames() async {
        guard !isLoading else { return }
        isLoading = true
        let names = await TableGamesAPI.loadDistinctNames()
        await MainActor.run {
            dynamicGames = names
            isLoading = false
        }
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

    private var closedWithWL: [Session] {
        sessions.filter { $0.winLoss != nil && $0.gameCategory == .poker }
    }

    private var totalProfit: Int {
        closedWithWL.compactMap { $0.winLoss }.filter { $0 > 0 }.reduce(0, +)
    }

    private var totalLoss: Int {
        abs(closedWithWL.compactMap { $0.winLoss }.filter { $0 < 0 }.reduce(0, +))
    }

    private var totalHours: Double {
        closedWithWL.reduce(0.0) { $0 + $1.hoursPlayed }
    }

    private var hourlyRate: Double? {
        let net = closedWithWL.compactMap { $0.winLoss }.reduce(0, +)
        guard totalHours > 0 else { return nil }
        return Double(net) / totalHours
    }

    private var roiPercent: Double? {
        let totalInitial = closedWithWL.compactMap { $0.initialBuyIn }.reduce(0, +)
        guard totalInitial > 0 else { return nil }
        let net = closedWithWL.compactMap { $0.winLoss }.reduce(0, +)
        return (Double(net) / Double(totalInitial)) * 100.0
    }

    private var winRate: Double? {
        let wins = closedWithWL.filter { ($0.winLoss ?? 0) > 0 }.count
        guard !closedWithWL.isEmpty else { return nil }
        return Double(wins) / Double(closedWithWL.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Poker Performance")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if let range = dateRangeText {
                    Text(range)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
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
            guard let wl = s.winLoss, let bi = s.initialBuyIn, bi > 0 else { return nil }
            let roi = (Double(wl) / Double(bi)) * 100.0
            return Point(date: s.startTime, roi: roi)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Poker ROI Over Time")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            if points.isEmpty {
                Text("Add a few poker sessions to see ROI trends over time.")
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
                let v = Int(selectedValue) ?? 0
                let idx = Self.values.firstIndex(where: { $0 >= v }) ?? 0
                wheelIndex = min(idx, Self.values.count - 1)
            }
        } else {
            // Fallback on earlier versions
        }
    }
}

// MARK: - Initial buy-in grid (popup with big squares)
struct BuyInGridSheet: View {
    let amounts: [Int]
    @Binding var selected: String
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedAmounts: Set<Int> = []

    private var totalSelected: Int {
        selectedAmounts.reduce(0, +)
    }

    var body: some View {
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
                        Text(
                            totalSelected > 0
                            ? "Total buy-in: \(settingsStore.currencySymbol)\(totalSelected)"
                            : "Select one or more amounts."
                        )
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        
                        Button {
                            guard totalSelected > 0 else { return }
                            selected = "\(totalSelected)"
                            dismiss()
                        } label: {
                            Text(
                                totalSelected > 0
                                ? "Good Luck - Buying in for \(settingsStore.currencySymbol)\(totalSelected)"
                                : "Good Luck"
                            )
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
            .navigationTitle("Initial Buy-In")
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
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Add Buy-In")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Tap a common denomination or enter a custom amount.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(quickBuyIns, id: \.self) { amt in
                            Button {
                                pendingTotal += amt
                            } label: {
                                Text("\(settingsStore.currencySymbol)\(amt)")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity, minHeight: 70)
                                    .background(Color.green)
                                    .foregroundColor(.black)
                                    .cornerRadius(16)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        TextField("Custom amount", text: $customAmount)
                            .textFieldStyle(DarkTextFieldStyle())
                            .keyboardType(.numberPad)
                        Button {
                            if let a = Int(customAmount), a > 0 {
                                pendingTotal += a
                                customAmount = ""
                            }
                        } label: {
                            Text("Add Custom Amount to Total")
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
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Buy-In")
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

    private func triggerHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// High-level sound events we care about. Each profile can map these to different files.
    private enum Event {
        case quickChime
        case bigWin
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
}

enum TransparentLogoCache {
    static var image: UIImage? = {
        UIImage(named: "LogoSplash")?.withBlackPixelsMadeTransparent()
    }()
}
#endif
