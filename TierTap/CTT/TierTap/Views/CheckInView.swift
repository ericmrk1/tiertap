import SwiftUI

struct CheckInView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedGame = ""
    @State private var casino = ""
    @State private var startingTier = ""
    @State private var initialBuyIn = ""
    @State private var showGamePicker = false
    @State private var showExistingAlert = false

    let quickBuyIns = [100, 200, 300, 500, 1000]

    var isValid: Bool {
        !selectedGame.isEmpty && !casino.isEmpty &&
        (Int(startingTier) != nil) && (Int(initialBuyIn) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Game
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Casino Game", systemImage: "suit.club.fill")
                                .font(.headline).foregroundColor(.white)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(GamesList.pinned, id: \.self) { g in
                                    GameButton(title: g, isSelected: selectedGame == g) { selectedGame = g }
                                }
                            }
                            Button { showGamePicker = true } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(GamesList.pinned.contains(selectedGame) || selectedGame.isEmpty
                                         ? "More games..." : selectedGame)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(12)
                                .background(!GamesList.pinned.contains(selectedGame) && !selectedGame.isEmpty
                                            ? Color.green.opacity(0.2) : Color(.systemGray6).opacity(0.25))
                                .foregroundColor(!GamesList.pinned.contains(selectedGame) && !selectedGame.isEmpty
                                                ? .white : .gray)
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Casino
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Casino Location", systemImage: "building.columns")
                                .font(.headline).foregroundColor(.white)
                            TextField("Enter casino name", text: $casino)
                                .textFieldStyle(DarkTextFieldStyle())
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Starting Tier
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Starting Tier Points", systemImage: "star.circle")
                                .font(.headline).foregroundColor(.white)
                            Text("Check your casino loyalty app and enter your current tier points.")
                                .font(.caption).foregroundColor(.gray)
                            TextField("e.g. 12500", text: $startingTier)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        // Buy-In
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Initial Buy-In", systemImage: "dollarsign.circle")
                                .font(.headline).foregroundColor(.white)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(quickBuyIns, id: \.self) { amt in
                                        Button("$\(amt)") { initialBuyIn = "\(amt)" }
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(initialBuyIn == "\(amt)" ? Color.green : Color(.systemGray6).opacity(0.25))
                                            .foregroundColor(initialBuyIn == "\(amt)" ? .black : .white)
                                            .cornerRadius(8).font(.subheadline)
                                    }
                                }
                            }
                            TextField("Or enter amount", text: $initialBuyIn)
                                .textFieldStyle(DarkTextFieldStyle())
                                .keyboardType(.numberPad)
                            if settingsStore.unitSize > 0, (Int(initialBuyIn) ?? 0) > settingsStore.unitSize {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Buy-in ($\(initialBuyIn)) exceeds your unit size ($\(settingsStore.unitSize)). Consider lowering to stay within bankroll target.")
                                        .font(.caption).foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.15))
                        .cornerRadius(16)

                        Button {
                            if store.liveSession != nil { showExistingAlert = true } else { go() }
                        } label: {
                            Text("Start Tracking")
                                .frame(maxWidth: .infinity).padding()
                                .background(isValid ? Color.green : Color.gray)
                                .foregroundColor(isValid ? .black : .white)
                                .cornerRadius(14).font(.headline)
                        }
                        .disabled(!isValid)
                    }
                    .padding()
                }
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showGamePicker) {
                GamePickerView(selectedGame: $selectedGame)
                    .presentationDetents([.medium, .large])
            }
            .alert("Active Session", isPresented: $showExistingAlert) {
                Button("Resume Existing", role: .cancel) { dismiss() }
                Button("End & Start New", role: .destructive) { store.discardLiveSession(); go() }
            } message: {
                Text("You have a live session. Resume it or end it to start a new one?")
            }
        }
    }

    func go() {
        guard let tier = Int(startingTier), let buy = Int(initialBuyIn) else { return }
        store.startSession(game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: buy)
        dismiss()
    }
}
