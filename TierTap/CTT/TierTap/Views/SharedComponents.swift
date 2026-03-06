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
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(amounts, id: \.self) { amt in
                    Button("$\(amt)") { selected = "\(amt)" }
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
    private var favorites: [String] { settingsStore.favoriteGames }
    private var filteredAll: [String] {
        search.isEmpty ? GamesList.all : GamesList.all.filter { $0.lowercased().contains(search.lowercased()) }
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
                                    Text("$\(amt)")
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
                            ? "Total buy-in: $\(totalSelected)"
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
                                ? "Good Luck - Buying in for $\(totalSelected)"
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
                                Text("$\(amt)")
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
                            Text(pendingTotal > 0 ? "Current buy-in total: $\(pendingTotal)" : "Tap amounts to build a buy-in, then confirm.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)

                            Button {
                                guard pendingTotal > 0 else { return }
                                onAdd(pendingTotal)
                                dismiss()
                            } label: {
                                Text(pendingTotal > 0 ? "Add $\(pendingTotal)" : "Add Buy-In")
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
        playSound()
    }

    private func triggerHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func playSound() {
        if let url = Bundle.main.url(forResource: "win-celebration", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } else {
            AudioServicesPlaySystemSound(1117)
        }
    }
}

struct ConfettiCelebrationView: View {
    let colors: [Color] = [.green, .yellow, .orange, .pink, .purple]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<60, id: \.self) { index in
                    ConfettiPiece(
                        index: index,
                        containerSize: geo.size,
                        color: colors.randomElement() ?? .green
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let containerSize: CGSize
    let color: Color
    @State private var yOffset: CGFloat = -200
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0

    var body: some View {
        let size = CGFloat(Int.random(in: 6...14))
        RoundedRectangle(cornerRadius: size / 3)
            .fill(color)
            .frame(width: size, height: size * 1.6)
            .rotationEffect(.degrees(rotation))
            .offset(x: xOffset, y: yOffset)
            .onAppear {
                let startX = CGFloat.random(in: -containerSize.width/2...containerSize.width/2)
                xOffset = startX
                yOffset = -containerSize.height / 2 - CGFloat.random(in: 0...150)
                let fallDistance = containerSize.height + 400
                let delay = Double(index) * 0.01
                withAnimation(.easeOut(duration: 1.8).delay(delay)) {
                    yOffset = fallDistance / 2
                }
                withAnimation(.linear(duration: 1.8).delay(delay)) {
                    rotation = Double.random(in: 180...720)
                }
            }
    }
}
