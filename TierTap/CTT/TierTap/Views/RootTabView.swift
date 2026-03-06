import SwiftUI

enum MainTab: Hashable {
    case sessions
    case history
    case risk
    case analytics
    case community
    case settings
}

struct RootTabView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedTab: MainTab = .sessions

    var body: some View {
        TabView(selection: $selectedTab) {
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.pie.fill")
                }
                .tag(MainTab.analytics)

            RiskOfRuinView()
                .tabItem {
                    Label("Risk of Ruin", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(MainTab.risk)

            HomeView()
                .tabItem {
                    Label("Sessions", systemImage: "play.circle.fill")
                }
                .tag(MainTab.sessions)

            CommunitySessionsView()
                .tabItem {
                    Label("Community", systemImage: "person.3.sequence.fill")
                }
                .tag(MainTab.community)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
        }
        .tint(settingsStore.primaryColor)
    }
}

struct CommunitySessionsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(settingsStore.primaryGradient)
                    Text("Community Sessions")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("This feature is coming soon. Soon you’ll be able to see anonymized community trends, compare your play to other advantage players, and discover new ways to optimize your sessions.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Community Sessions")
            .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

