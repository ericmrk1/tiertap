import SwiftUI

/// Presents basic strategy and odds for a table game. Content is generic and can be found in many
/// strategy guides, books, and online resources. Shows a disclaimer that some information may change over time.
struct StrategyOddsSheet: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss

    let gameName: String

    private var entry: StrategyDatabase.Entry? {
        StrategyDatabase.entry(forGame: gameName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let entry = entry {
                            Text(entry.summary)
                                .font(.body)
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No strategy summary is available for \"\(gameName)\" in this app. For rules, strategy, and current odds, search for your game in strategy guides, books, or reputable gambling-research sources.")
                                .font(.body)
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            if let url = StrategyDatabase.wikipediaURL(forGame: gameName) {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                        Text("Wikipedia: \(gameName)")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                }
                                .padding(.top, 4)
                            }
                        }

                        // Disclaimer at bottom
                        Text("Some of this information may change over time. Rules, paytables, and house edges vary by casino and game version. For current details, consult multiple sources or the casino.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(gameName.isEmpty ? "Strategy / Odds" : "\(gameName) — Strategy / Odds")
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
    }
}
