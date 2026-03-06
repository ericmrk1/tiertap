import SwiftUI

struct WatchStartView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedGame = "Blackjack"
    @State private var casino = ""
    @State private var startingTier = "0"
    @State private var selectedBuyIn = 100
    @State private var showStartConfirm = false

    let games = GamesList.pinned
    let buyInOptions = [100, 200, 300, 500]

    var canStart: Bool {
        !casino.isEmpty && Int(startingTier) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start Session")
                    .font(.headline)

                Picker("Game", selection: $selectedGame) {
                    ForEach(games, id: \.self) { g in
                        Text(g).tag(g)
                    }
                }
                .labelsHidden()

                TextField("Casino", text: $casino)

                TextField("Tier pts", text: $startingTier)

                Text("Buy-in").font(.caption)
                HStack(spacing: 6) {
                    ForEach(buyInOptions, id: \.self) { amt in
                        Button("$\(amt)") { selectedBuyIn = amt }
                            .buttonStyle(.bordered)
                            .tint(selectedBuyIn == amt ? .green : .gray)
                    }
                }

                Button {
                    showStartConfirm = true
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canStart)
            }
            .padding()
        }
        .navigationTitle("TierTap")
        .confirmationDialog("Start session?", isPresented: $showStartConfirm) {
            Button("Start") { startSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedGame) at \(casino), $\(selectedBuyIn) buy-in")
        }
    }

    private func startSession() {
        guard let tier = Int(startingTier) else { return }
        store.startSession(game: selectedGame, casino: casino, startingTier: tier, initialBuyIn: selectedBuyIn)
    }
}
