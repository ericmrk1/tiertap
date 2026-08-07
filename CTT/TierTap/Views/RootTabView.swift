import SwiftUI
import MapKit
import StoreKit
import UIKit

enum MainTab: Hashable {
    case sessions
    case history
    case journal
    case trips
    case analytics
    case community
    case wallet
    case settings

    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .history: return "History"
        case .journal: return "Journal"
        case .trips: return "Trips"
        case .analytics: return "Analytics"
        case .community: return "Community"
        case .wallet: return "Wallet"
        case .settings: return "Settings"
        }
    }

    /// Short one-word label shown under the tab icon when tab bar labels are enabled.
    var tabBarLabel: String {
        switch self {
        case .sessions: return "Play"
        case .history: return "History"
        case .journal: return "Journal"
        case .trips: return "Trips"
        case .analytics: return "Analytics"
        case .community: return "Feed"
        case .wallet: return "Wallet"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: return "play.circle.fill"
        case .history: return "clock.fill"
        case .journal: return "book.fill"
        case .trips: return "suitcase.fill"
        case .analytics: return "chart.pie.fill"
        case .community: return "person.3.sequence.fill"
        case .wallet: return "wallet.pass.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @StateObject private var tabBarChrome = FloatingTabBarChrome()
    @State private var selectedTab: MainTab = .sessions
    @State private var showGASupportFromMoodDownswing = false

    /// All root tabs stay on a custom bar (no system “More” overflow once Journal is on).
    /// Sessions stays in the middle so the play control can be centered in the pill.
    private var visibleTabs: [MainTab] {
        var tabs: [MainTab] = [.analytics, .trips, .community, .sessions]
        if TierTapProductEnhancements.isSprint2Active {
            tabs.append(.journal)
        }
        tabs.append(.wallet)
        tabs.append(.settings)
        return tabs
    }

    var body: some View {
        ZStack {
            tabContent
                .background {
                    FloatingTabBarScrollObserver {
                        tabBarChrome.noteScrollActivity()
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(settingsStore.primaryColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar(
                selection: $selectedTab,
                tabs: visibleTabs,
                isMinimized: tabBarChrome.isMinimized,
                isLiveSession: sessionStore.liveSession != nil
            )
        }
        .environmentObject(tabBarChrome)
        .onChange(of: selectedTab) { _ in
            tabBarChrome.expandImmediately()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMoodDownswingNeedsGASupport)) { _ in
            showGASupportFromMoodDownswing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSessionsTabFromDeepLink"))) { _ in
            selectedTab = .sessions
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAnalyticsTabFromDeepLink"))) { _ in
            selectedTab = .analytics
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenTripsTabFromDeepLink"))) { _ in
            selectedTab = .trips
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenJournalTabFromDeepLink"))) { _ in
            guard TierTapProductEnhancements.isSprint2Active else { return }
            selectedTab = .journal
        }
        .onReceive(NotificationCenter.default.publisher(for: TierTapProductEnhancements.showJournalNotificationName)) { _ in
            guard TierTapProductEnhancements.isSprint2Active else { return }
            selectedTab = .journal
        }
        .onReceive(NotificationCenter.default.publisher(for: TierTapProductEnhancements.showTripPrepNotificationName)) { _ in
            selectedTab = .sessions
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWalletFromDeepLink"))) { _ in
            selectedTab = .wallet
        }
        #if os(iOS)
        .adaptiveSheet(isPresented: $showGASupportFromMoodDownswing) {
            GASupportSheet(onDismiss: {
                showGASupportFromMoodDownswing = false
            })
            .environmentObject(settingsStore)
            .environment(\.appLanguage, settingsStore.appLanguage)
        }
        #endif
    }

    /// Keep each root screen alive so navigation state survives tab switches (no system TabView / More bar).
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            tabPage(.analytics) { AnalyticsView() }
            tabPage(.trips) { TripsView() }
            tabPage(.sessions) { HomeView() }
            tabPage(.community) {
                CommunitySessionsView()
                    .id(authStore.isSignedIn)
            }
            if TierTapProductEnhancements.isSprint2Active {
                tabPage(.journal) { JournalTabView() }
            }
            tabPage(.wallet) {
                TierTapWalletView(isRootTab: true)
            }
            tabPage(.settings) { SettingsView() }
        }
    }

    @ViewBuilder
    private func tabPage<Content: View>(_ tab: MainTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

// MARK: - Custom tab bar (fits Community without system More)

@MainActor
final class FloatingTabBarChrome: ObservableObject {
    @Published private(set) var isMinimized = false

    private var expandWorkItem: DispatchWorkItem?
    private let expandDelay: TimeInterval = 0.42

    func noteScrollActivity() {
        if !isMinimized {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                isMinimized = true
            }
        }
        scheduleExpand()
    }

    func expandImmediately() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard isMinimized else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
            isMinimized = false
        }
    }

    private func scheduleExpand() {
        expandWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                self.isMinimized = false
            }
        }
        expandWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: work)
    }
}

/// Observes vertical `UIScrollView` offset changes under the tab content to collapse the floating pill.
private struct FloatingTabBarScrollObserver: UIViewRepresentable {
    var onScrollActivity: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollActivity: onScrollActivity)
    }

    func makeUIView(context: Context) -> UIView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onAttach = { [weak coordinator = context.coordinator] probe in
            coordinator?.refresh(from: probe)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onScrollActivity = onScrollActivity
        context.coordinator.refresh(from: uiView)
    }

    final class Coordinator {
        var onScrollActivity: () -> Void
        private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]

        init(onScrollActivity: @escaping () -> Void) {
            self.onScrollActivity = onScrollActivity
        }

        func refresh(from view: UIView) {
            let root = hostRootView(from: view) ?? view.window
            guard let root else { return }

            var found = Set<ObjectIdentifier>()
            for scroll in Self.collectScrollViews(from: root) {
                let id = ObjectIdentifier(scroll)
                found.insert(id)
                guard observations[id] == nil else { continue }
                observations[id] = scroll.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                    guard let old = change.oldValue, let new = change.newValue else { return }
                    // Collapse only on vertical movement (ignore horizontal chip/carousels).
                    guard abs(new.y - old.y) >= 1.0 else { return }
                    DispatchQueue.main.async {
                        self?.onScrollActivity()
                    }
                }
            }

            observations = observations.filter { found.contains($0.key) }
        }

        private func hostRootView(from view: UIView) -> UIView? {
            var responder: UIResponder? = view
            while let current = responder {
                if let viewController = current as? UIViewController {
                    return viewController.view
                }
                responder = current.next
            }
            return view.superview
        }

        private static func collectScrollViews(from root: UIView) -> [UIScrollView] {
            var result: [UIScrollView] = []
            func walk(_ view: UIView) {
                if let scroll = view as? UIScrollView {
                    result.append(scroll)
                }
                for subview in view.subviews {
                    walk(subview)
                }
            }
            walk(root)
            return result
        }
    }

    private final class ProbeView: UIView {
        var onAttach: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onAttach?(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onAttach?(self)
        }
    }
}

private struct MainTabBar: View {
    @Binding var selection: MainTab
    let tabs: [MainTab]
    var isMinimized: Bool
    var isLiveSession: Bool
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.appLanguage) private var language

    private var showLabels: Bool {
        settingsStore.showTabBarLabels && !isMinimized
    }

    /// Live sessions shrink the pill 20%; scroll collapse stacks on top of that.
    private var scale: CGFloat {
        let liveScale: CGFloat = isLiveSession ? 0.95 : 1.0
        return isMinimized ? liveScale * 0.70 : liveScale
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(for: tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, showLabels ? 5 : 7)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.42))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .scaleEffect(scale, anchor: .bottom)
        .opacity(isMinimized ? 0.72 : 1.0)
        .offset(y: isMinimized ? 10 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isLiveSession)
        .allowsHitTesting(!isMinimized)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(isMinimized)
    }

    private func tabButton(for tab: MainTab) -> some View {
        MainTabBarItem(
            tab: tab,
            isSelected: selection == tab,
            showLabel: showLabels,
            language: language
        ) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                selection = tab
            }
        }
    }
}

private struct MainTabBarItem: View {
    let tab: MainTab
    let isSelected: Bool
    let showLabel: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: showLabel ? 2 : 0) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: isSelected ? 20 : 18, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))

                if showLabel {
                    Text(L10n.tr(tab.tabBarLabel, language: language))
                        .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: showLabel ? 52 : 40)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                }
            }
            .scaleEffect(isSelected ? 1.06 : 0.94)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr(tab.title, language: language))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CommunitySessionsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var tabBarChrome: FloatingTabBarChrome
    @State private var showAuthSheet = false
    @State private var emailInput = ""
    @State private var isPublishSelectorPresented = false
    @State private var publishErrorMessage: String?
    @State private var feedSessions: [TableGamePostRow] = []
    @State private var selectedGames: Set<String> = []
    @State private var selectedLocations: Set<String> = []
    @State private var selectedScreenNames: Set<String> = []
    @State private var screenNameSearchText: String = ""
    @State private var isLoadingFeed = false
    @State private var feedErrorMessage: String?
    @State private var availableGames: [String] = []
    @State private var availableLocations: [String] = []
    @State private var availableScreenNames: [String] = []
    @State private var filterStartDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-24 * 60 * 60)
    @State private var filterEndDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var showMapSheet = false
    @State private var mapSessions: [TableGamePostRow] = []
    @State private var hasMoreFeedPages = false
    @State private var locationLookup: [String: CLLocationCoordinate2D] = [:]
    @State private var isPreloadingLocationLookup = false
    @State private var showProPaywall = false
    /// Aggregated like / dislike / heart counts keyed by post id.
    @State private var reactionSummaries: [Int64: CommunityPostReactionSummary] = [:]
    @State private var reactionInFlightPostIds: Set<Int64> = []
    @State private var selectedAuthor: CommunityAuthorRef?

    /// Free (non-Pro) users see at most this many feed entries in the clear; the rest are blurred behind Pro.
    private static let freeFeedEntryLimit = 5
    /// Clears the floating pill tab bar (nested `safeAreaInset` draws under it).
    private static let publishButtonPillClearance: CGFloat = 82
    /// Approximate height of the floating + control (+ optional status line) for scroll content inset.
    private static let publishButtonContentHeight: CGFloat = 56

    private var showsPublishButton: Bool {
        SupabaseConfig.isConfigured
            && authStore.isSignedIn
            && !sessionStore.sessions.isEmpty
    }

    private var publishButtonAccessibilityLabel: String {
        TierTapProductEnhancements.isEnabled && !canPublishToCommunity
            ? "Publish with TierTap Pro"
            : "Pick Sessions To Publish"
    }

    private var publishFloatingButton: some View {
        Button {
            if TierTapProductEnhancements.isEnabled && !canPublishToCommunity {
                showProPaywall = true
            } else {
                isPublishSelectorPresented = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(settingsStore.primaryGradient)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(publishButtonAccessibilityLabel)
        // Shrink while scrolling so the feed stays readable; expands again when scrolling stops.
        .scaleEffect(tabBarChrome.isMinimized ? 0.1 : 1.0, anchor: .bottomTrailing)
        .opacity(tabBarChrome.isMinimized ? 0.55 : 1.0)
        .allowsHitTesting(!tabBarChrome.isMinimized)
        .accessibilityHidden(tabBarChrome.isMinimized)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: tabBarChrome.isMinimized)
    }

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    /// Legacy: whole Community tab behind Pro. When enhancements are on, browse is free (sign-in still required for feed data).
    private var shouldShowCommunityPaywall: Bool {
        if TierTapProductEnhancements.isEnabled { return false }
        return !hasProAccess || !authStore.isSignedIn || settingsStore.isProTokenBackedAccessBlocked(hasProAccess: hasProAccess)
    }

    private var canPublishToCommunity: Bool {
        hasProAccess
            && authStore.isSignedIn
            && !settingsStore.isProTokenBackedAccessBlocked(hasProAccess: hasProAccess)
    }

    /// Signed-in non-Pro with unpublished completed sessions — soft Pro upsell.
    private var shouldShowLurkerUpsell: Bool {
        TierTapProductEnhancements.isSprint2Active
            && authStore.isSignedIn
            && !canPublishToCommunity
            && sessionStore.sessions.contains { $0.isComplete && !$0.isPublishedToCommunity }
    }

    private var anonymousFeedLabel: String {
        L10n.tr("Anonymous", language: settingsStore.appLanguage)
    }

    private var visibleFeedSessions: [TableGamePostRow] {
        feedSessions.filter { item in
            let gameName = (item.game ?? item.session_details?.game ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let locationName = (item.location ?? item.session_details?.casino ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let matchesGame: Bool
            if selectedGames.isEmpty {
                matchesGame = true
            } else if gameName.isEmpty {
                matchesGame = false
            } else {
                matchesGame = selectedGames.contains(gameName)
            }

            let matchesLocation: Bool
            if selectedLocations.isEmpty {
                matchesLocation = true
            } else if locationName.isEmpty {
                matchesLocation = false
            } else {
                matchesLocation = selectedLocations.contains(locationName)
            }

            let matchesScreenNameBubbles: Bool
            if selectedScreenNames.isEmpty {
                matchesScreenNameBubbles = true
            } else if let screenName = item.feedScreenName {
                matchesScreenNameBubbles = selectedScreenNames.contains(screenName)
            } else {
                matchesScreenNameBubbles = selectedScreenNames.contains(anonymousFeedLabel)
            }

            let screenNameQuery = screenNameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesScreenNameSearch: Bool
            if screenNameQuery.isEmpty {
                matchesScreenNameSearch = true
            } else if let screenName = item.feedScreenName {
                matchesScreenNameSearch = screenName.localizedStandardContains(screenNameQuery)
            } else {
                matchesScreenNameSearch = anonymousFeedLabel.localizedStandardContains(screenNameQuery)
            }

            return matchesGame && matchesLocation && matchesScreenNameBubbles && matchesScreenNameSearch
        }
    }

    var body: some View {
        NavigationStack {
            if shouldShowCommunityPaywall {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            } else {
                ZStack {
                    settingsStore.primaryGradient.ignoresSafeArea()
                    // Filters stay fixed above the scrolling feed (same pattern as History).
                    VStack(spacing: 0) {
                        CommunityFeedFiltersView(
                            filterStartDate: $filterStartDate,
                            filterEndDate: $filterEndDate,
                            selectedGames: $selectedGames,
                            selectedLocations: $selectedLocations,
                            selectedScreenNames: $selectedScreenNames,
                            screenNameSearchText: $screenNameSearchText,
                            availableGames: availableGames,
                            availableLocations: availableLocations,
                            availableScreenNames: availableScreenNames,
                            isLoading: isLoadingFeed,
                            onApply: {
                                Task { await reloadCommunityFeed() }
                            },
                            onClear: {
                                filterStartDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-24 * 60 * 60)
                                filterEndDate = Date()
                                selectedGames.removeAll()
                                selectedLocations.removeAll()
                                selectedScreenNames.removeAll()
                                screenNameSearchText = ""
                                Task { await reloadCommunityFeed() }
                            }
                        )

                        ScrollView {
                    VStack(spacing: 16) {

                        if shouldShowLurkerUpsell {
                            Button {
                                showProPaywall = true
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "person.3.sequence.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Share what you’re logging")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white)
                                        Text("You’ve got unpublished sessions. Pro unlocks publishing to Community — browsing stays free.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Text("Pro")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green)
                                        .clipShape(Capsule())
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        if let error = feedErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        if !SupabaseConfig.isConfigured {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.yellow)
                                L10nText("Connect Supabase to see the community feed.")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 24)
                        } else if !authStore.isSignedIn {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.exclam")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                                L10nText("Sign in to view the community feed.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                L10nText("Use the Account button in the top right to sign in.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 32)
                        } else if isLoadingFeed && feedSessions.isEmpty {
                            ProgressView("Loading community sessions…")
                                .tint(.white)
                                .padding(.top, 32)
                        } else if feedSessions.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.3.sequence.fill")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                L10nText("No community sessions have been published yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                L10nText("Be the first to publish your sessions using the + button.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 32)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(visibleFeedSessions.enumerated()), id: \.element.id) { index, item in
                                    if !hasProAccess && index >= Self.freeFeedEntryLimit {
                                        lockedFeedRow(for: item)
                                    } else {
                                        CommunityFeedRow(
                                            item: item,
                                            reactionSummary: reactionSummaries[item.id] ?? .empty,
                                            canReact: canPublishToCommunity,
                                            isReactionBusy: reactionInFlightPostIds.contains(item.id),
                                            onShowLocation: { row in
                                                presentCommunityMap(with: [row])
                                            },
                                            onOpenAuthor: {
                                                selectedAuthor = CommunityAuthorRef(
                                                    from: item,
                                                    anonymousLabel: anonymousFeedLabel
                                                )
                                            },
                                            onReact: { type in
                                                Task { await toggleCommunityReaction(postId: item.id, type: type) }
                                            },
                                            onReactBlocked: {
                                                showProPaywall = true
                                            }
                                        )
                                            .environmentObject(settingsStore)
                                            .environmentObject(authStore)
                                            .padding(.horizontal)
                                    }
                                }

                                // Free users already see blurred rows past the limit; loading more pages
                                // would only add more locked entries, so keep the button Pro-only then.
                                if hasMoreFeedPages && (hasProAccess || visibleFeedSessions.count < Self.freeFeedEntryLimit) {
                                    Button {
                                        Task { await loadMoreCommunityFeed() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isLoadingFeed {
                                                ProgressView()
                                                    .tint(.white)
                                            } else {
                                                Image(systemName: "arrow.down.circle.fill")
                                                L10nText("Load more")
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(14)
                                        .padding(.top, 8)
                                        .padding(.horizontal)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoadingFeed)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.top, 8)
                    .padding(
                        .bottom,
                        showsPublishButton
                            ? Self.publishButtonContentHeight + Self.publishButtonPillClearance
                            : 24
                    )
                        }
                        .refreshable {
                            await reloadCommunityFeed()
                        }
                    }
                }
            .overlay(alignment: .bottomTrailing) {
                if showsPublishButton {
                    VStack(alignment: .trailing, spacing: 8) {
                        if !tabBarChrome.isMinimized {
                            if let error = publishErrorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.9))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 220, alignment: .trailing)
                                    .transition(.opacity)
                            }
                        }
                        publishFloatingButton
                    }
                    .padding(.trailing, 16)
                    // Sit above the floating pill (nested safeAreaInset was drawing under it).
                    .padding(.bottom, Self.publishButtonPillClearance)
                }
            }
            .localizedNavigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if SupabaseConfig.isConfigured, authStore.isSignedIn, !visibleFeedSessions.isEmpty {
                        Button {
                            presentCommunityMap(with: visibleFeedSessions)
                        } label: {
                            L10nText("🌐")
                                .font(.title2)
                        }
                        .foregroundColor(.white)
                        .accessibilityLabel("Show session locations on map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAuthSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            if authStore.isSignedIn,
                               let uiImage = authStore.localProfilePhotoImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                                    )
                            } else {
                                Image(systemName: authStore.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                            }
                            if authStore.isSignedIn {
                                if authStore.localProfilePhotoImage == nil,
                                   let emojis = authStore.userProfileEmojis,
                                   !emojis.isEmpty {
                                    Text(emojis)
                                        .font(.caption)
                                }
                                Text(authStore.signedInSummary ?? authStore.userEmail ?? "Account")
                                    .lineLimit(1)
                                    .font(.caption)
                            } else {
                                L10nText("Account")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .task {
                await loadCommunityFeedIfNeeded()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedAuthor != nil },
                set: { if !$0 { selectedAuthor = nil } }
            )) {
                if let author = selectedAuthor {
                    CommunityAuthorProfileView(
                        author: author,
                        canReact: canPublishToCommunity,
                        onShowLocation: { row in
                            presentCommunityMap(with: [row])
                        },
                        onReactBlocked: {
                            showProPaywall = true
                        }
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                }
            }
            .adaptiveSheet(isPresented: $showAuthSheet) {
                CommunityAuthSheet(
                    emailInput: $emailInput,
                    onDismiss: { showAuthSheet = false }
                )
                .environmentObject(authStore)
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
            }
            .adaptiveSheet(isPresented: $isPublishSelectorPresented) {
                CommunitySessionPublishSelectionView(
                    sessions: sessionStore.sessions.filter { $0.isComplete }
                ) { result in
                    switch result {
                    case .success(let count):
                        publishErrorMessage = nil
                        sessionStore.communityPublishToastMessage = count == 1 ?
                            "Published 1 session to the community." :
                            "Published \(count) sessions to the community."
                    case .failure(let error):
                        publishErrorMessage = error.localizedDescription
                    }
                }
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(sessionStore)
            }
            .adaptiveSheet(isPresented: $showProPaywall) {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            }
            .adaptiveSheet(isPresented: $showMapSheet) {
                CommunityFeedMapSheet(
                    sessions: mapSessions,
                    locationLookup: locationLookup,
                    isLocationLookupLoading: isPreloadingLocationLookup
                )
                .environmentObject(settingsStore)
            }
            }
        }
    }
}

// MARK: - Account / auth sheet (login info + options)
struct CommunityAuthSheet: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.appLanguage) private var appLanguage
    @Binding var emailInput: String
    var onDismiss: () -> Void

    @State private var profileDisplayName: String = ""
    @State private var profileEmojis: String = ""
    @State private var profilePhoto: UIImage?
    @State private var isSavingProfile = false
    @State private var showProfileSavedAlert = false
    @State private var isShowingCameraPicker = false
    @State private var isShowingLibraryPicker = false
    @State private var showSubscriptionPaywall = false
    @State private var isPurchasingCreditsPack = false
    @State private var isConfirmingDeleteAccount = false

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
    }

    private var subscriptionPlanLabel: String {
        if settingsStore.isSubscriptionOverrideActive {
            return L10n.tr("TierTap Pro (developer override)", language: appLanguage)
        }
        if subscriptionStore.purchasedProductIds.isEmpty {
            return L10n.tr("None (free tier)", language: appLanguage)
        }
        let id = subscriptionStore.purchasedProductIds.sorted().first!
        if let product = subscriptionStore.products.first(where: { $0.id == id }) {
            return product.displayName
        }
        switch id {
        case TierTapProductId.monthly.rawValue:
            return L10n.tr("TierTap Pro — Monthly", language: appLanguage)
        case TierTapProductId.quarterly.rawValue:
            return L10n.tr("TierTap Pro — Quarterly", language: appLanguage)
        case TierTapProductId.yearly.rawValue:
            return L10n.tr("TierTap Pro — Yearly", language: appLanguage)
        case TierTapProductId.credits.rawValue:
            return L10n.tr("AI token pack (Credits)", language: appLanguage)
        default:
            return L10n.tr("TierTap Pro", language: appLanguage)
        }
    }

    private var aiTokenPacksAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedLabel(title: "AI token packs", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            TierTapPlusTokenStatBubbles(
                packBalance: settingsStore.aiPurchasedTokenBalance,
                lifetimePurchased: settingsStore.lifetimeTierTapPlusTokensPurchased,
                packUsage: settingsStore.tierTapPlusTokensConsumedFromPurchases
            )

            Text(
                String(
                    format: L10n.tr("Pro plan tokens left this month: %@", language: appLanguage),
                    settingsStore.proPlanIncludedTokensRemainingThisMonth.formatted(.number.grouping(.automatic))
                )
            )
            .font(.caption2)
            .foregroundColor(.white.opacity(0.78))

            if let product = subscriptionStore.creditsProduct {
                Button {
                    Task { await purchaseCreditsPackFromAccount(product) }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        if isPurchasingCreditsPack {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "cart.fill")
                        }
                        let packCount = settingsStore.effectiveCreditsPackTokenAmount.formatted(.number.grouping(.automatic))
                        TierTapPlusTokenPackPurchaseLabel(
                            language: appLanguage,
                            tokenCountFormatted: packCount,
                            displayPrice: product.displayPrice,
                            font: .caption.weight(.semibold)
                        )
                    }
                    .tierTapPlusPurchaseButtonChrome(compact: false)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel(
                    String(
                        format: L10n.tr("Buy TierTap Plus Tokens (%@) — %@", language: appLanguage),
                        settingsStore.effectiveCreditsPackTokenAmount.formatted(.number.grouping(.automatic)),
                        product.displayPrice
                    )
                )
                .disabled(isPurchasingCreditsPack || subscriptionStore.isLoading)
            } else {
                L10nText("Token packs aren’t available in the store yet.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12))
        .cornerRadius(14)
    }

    private func purchaseCreditsPackFromAccount(_ product: Product) async {
        guard !isPurchasingCreditsPack, !subscriptionStore.isLoading else { return }
        isPurchasingCreditsPack = true
        if let tid = await subscriptionStore.purchase(product) {
            await settingsStore.grantTierTapSessionCreditsPack(
                storeTransactionId: tid,
                supabaseUserId: authStore.session?.user.id
            )
        }
        isPurchasingCreditsPack = false
    }

    private var subscriptionAccessRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 4) {
                    L10nText("Subscription:")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                    Text(subscriptionPlanLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 4)
                if hasProAccess {
                    Button {
                        showSubscriptionPaywall = true
                    } label: {
                        L10nText("Manage")
                            .font(.caption2.weight(.bold))
                            .underline()
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !hasProAccess {
                Button {
                    showSubscriptionPaywall = true
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "crown.fill")
                        L10nText("Subscribe")
                            .font(.caption.weight(.semibold))
                    }
                    .tierTapPlusPurchaseButtonChrome(compact: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Subscribe", language: appLanguage))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }

    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    authContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .localizedNavigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            profileDisplayName = authStore.userDisplayName ?? ""
            profileEmojis = authStore.userProfileEmojis ?? ""
            profilePhoto = authStore.localProfilePhotoImage
        }
        .onChange(of: authStore.session?.user.id) { _ in
            profileDisplayName = authStore.userDisplayName ?? ""
            profileEmojis = authStore.userProfileEmojis ?? ""
            profilePhoto = authStore.localProfilePhotoImage
        }
        .onChange(of: profilePhoto) { _ in
            if authStore.isSignedIn {
                saveProfile()
            }
        }
        .adaptiveSheet(isPresented: $isShowingCameraPicker) {
            ProfilePhotoCaptureView(image: $profilePhoto, preferredSourceType: .camera)
        }
        .adaptiveSheet(isPresented: $isShowingLibraryPicker) {
            ProfilePhotoCaptureView(image: $profilePhoto, preferredSourceType: .photoLibrary)
        }
        .adaptiveSheet(isPresented: $showSubscriptionPaywall) {
            TierTapPaywallView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
        }
        .task {
            await subscriptionStore.loadProducts()
        }
        .confirmationDialog(
            "Delete your TierTap account?",
            isPresented: $isConfirmingDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await authStore.deleteAccount()
                    if !authStore.isSignedIn {
                        onDismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            L10nText("This permanently deletes your TierTap account, Community profile, and synced cloud data. Sessions and settings stored only on this device are not deleted. This cannot be undone.")
        }
        .alert("Profile Saved", isPresented: $showProfileSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            L10nText("Your screen name and profile photo were saved.")
        }
        .presentationDetents([.large])
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            L10nText("Profile")
                .font(.headline.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        if let image = profilePhoto {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if let emojis = authStore.userProfileEmojis, !emojis.isEmpty {
                            Text(emojis)
                                .font(.system(size: 30))
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )

                    HStack(spacing: 6) {
                        Button {
                            isShowingCameraPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                L10nText("Camera")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            isShowingLibraryPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.caption)
                                L10nText("Photos")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                L10nText("Screen Name")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.9))
                TextField(L10n.tr("Shown on Community when you publish", language: appLanguage), text: $profileDisplayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .padding(10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .submitLabel(.done)
                    .onSubmit { saveProfile() }

                Button {
                    saveProfile()
                } label: {
                    HStack(spacing: 8) {
                        if isSavingProfile {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        }
                        Text(isSavingProfile ? "Saving…" : "Save profile")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.22))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isSavingProfile)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .cornerRadius(14)

            if let msg = authStore.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func saveProfile() {
        authStore.errorMessage = nil
        isSavingProfile = true
        Task {
            await authStore.updateProfile(
                displayName: profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                emojis: profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if authStore.errorMessage == nil {
                if let image = profilePhoto,
                   let data = image.jpegData(compressionQuality: 0.8) {
                    try? authStore.saveProfilePhotoLocally(data)
                    // Keep the public Community avatar in sync when the user updates Account.
                    try? await authStore.uploadProfilePhoto(data)
                } else {
                    try? authStore.deleteLocalProfilePhoto()
                    try? await authStore.deleteProfilePhoto()
                }
            }
            await MainActor.run {
                isSavingProfile = false
                if authStore.errorMessage == nil {
                    showProfileSavedAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private var authContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 72)
                    .shadow(radius: 6)

                L10nText("Your TierTap Account")
                    .font(.headline.bold())
                    .foregroundColor(.white)

                L10nText("Sign in to unlock advanced AI features, sync your data, and join Community sessions.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)
            }

            subscriptionAccessRow

            aiTokenPacksAccountCard

            if !SupabaseConfig.isConfigured {
                L10nText("Add SUPABASE_URL and SUPABASE_ANON_KEY to SupabaseKeys.plist to enable sign-in. You can still use TierTap without an account.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(10)
            } else if authStore.isSignedIn {
                // Profile: screen name & emojis (large section)
                profileSection

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        L10nText("Signed in")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        if let email = authStore.userEmail {
                            Text(email)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6).opacity(0.18))
                .cornerRadius(12)

                HStack(spacing: 10) {
                    Button("Log out", role: .destructive) {
                        authStore.signOut()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(authStore.isLoading)

                    Button("Delete Account", role: .destructive) {
                        isConfirmingDeleteAccount = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(authStore.isLoading)
                }

                if let msg = authStore.errorMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                TierTapAccountSignInSection(
                    emailInput: $emailInput,
                    compact: true,
                    showsBenefitsPitch: true,
                    onContinueWithoutAccount: onDismiss
                )
            }

            LockDownTierTapSection(compact: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Emoji Picker (big tappable grid)
private let profileEmojiOptions: [String] = [
    "🎲", "🃏", "♠️", "♥️", "♦️", "♣️", "🎰", "💰", "💵", "💴", "💎", "✨",
    "🔥", "⭐️", "🌟", "🎯", "🏆", "👑", "🦅", "🎪", "🎭", "🎬", "🍀", "🎴",
    "🀄️", "🧿", "💫", "✅", "🎉", "🚀", "💪", "😎", "🤑", "🤩"
]

struct EmojiPickerView: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
    private let emojiSize: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(profileEmojiOptions, id: \.self) { emoji in
                let isSelected = selection.contains(emoji)
                Button {
                    toggle(emoji: emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: emojiSize - 8))
                        .frame(width: emojiSize, height: emojiSize)
                        .background(isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.1))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
    }

    private func toggle(emoji: String) {
        if selection.contains(emoji) {
            selection = selection.replacingOccurrences(of: emoji, with: "")
        } else {
            selection.append(emoji)
        }
    }
}

// MARK: - Community feed helpers

extension CommunitySessionsView {
    private var communityPageSize: Int { 50 }

    /// Feed entry past the free limit: blurred content with a Pro unlock overlay; tapping opens the paywall.
    @ViewBuilder
    private func lockedFeedRow(for item: TableGamePostRow) -> some View {
        Button {
            showProPaywall = true
        } label: {
            CommunityFeedRow(
                item: item,
                reactionSummary: reactionSummaries[item.id] ?? .empty,
                canReact: false,
                isReactionBusy: false,
                onShowLocation: nil,
                onOpenAuthor: nil,
                onReact: nil,
                onReactBlocked: nil
            )
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .blur(radius: 7)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                        L10nText("Unlock with TierTap Pro")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Locked community session. Unlock with TierTap Pro.", language: settingsStore.appLanguage))
        .accessibilityAddTraits(.isButton)
    }

    private func refreshReactionSummaries(for posts: [TableGamePostRow]) async {
        let ids = posts.map(\.id)
        guard !ids.isEmpty else {
            await MainActor.run { reactionSummaries = [:] }
            return
        }
        let viewerId = await MainActor.run { authStore.session?.user.id }
        do {
            let summaries = try await CommunityPostReactionsAPI.fetchSummaries(
                postIds: ids,
                viewerUserId: viewerId
            )
            await MainActor.run {
                var merged = reactionSummaries
                for id in ids {
                    merged[id] = summaries[id] ?? .empty
                }
                reactionSummaries = merged
            }
        } catch {
            // Non-fatal: feed still works without reaction counts if the migration isn’t applied yet.
        }
    }

    private func toggleCommunityReaction(postId: Int64, type: CommunityReactionType) async {
        guard canPublishToCommunity else {
            await MainActor.run { showProPaywall = true }
            return
        }
        guard let userId = await MainActor.run(body: { authStore.session?.user.id }) else {
            await MainActor.run { showProPaywall = true }
            return
        }

        let alreadyBusy = await MainActor.run { reactionInFlightPostIds.contains(postId) }
        guard !alreadyBusy else { return }

        let prior = await MainActor.run { reactionSummaries[postId] ?? .empty }
        let currentlyActive = prior.viewerHas(type)
        let opposingActive: Bool = {
            switch type {
            case .like: return prior.viewerDisliked
            case .dislike: return prior.viewerLiked
            case .heart: return false
            }
        }()

        await MainActor.run {
            reactionInFlightPostIds.insert(postId)
            var next = prior
            next.applyOptimisticToggle(of: type)
            reactionSummaries[postId] = next
        }

        do {
            try await CommunityPostReactionsAPI.toggle(
                postId: postId,
                type: type,
                currentlyActive: currentlyActive,
                currentlyHasOpposingLikeDislike: opposingActive,
                userId: userId
            )
        } catch {
            await MainActor.run {
                reactionSummaries[postId] = prior
                feedErrorMessage = "Could not update reaction. Please try again."
            }
        }

        await MainActor.run {
            reactionInFlightPostIds.remove(postId)
        }
    }

    /// Opens the map sheet and ensures casino coordinates are loaded (or refreshed) for the given sessions.
    private func presentCommunityMap(with sessions: [TableGamePostRow]) {
        mapSessions = sessions
        showMapSheet = true
        Task {
            await preloadLocationLookup(for: sessions)
        }
    }

    private func loadCommunityFeedIfNeeded() async {
        guard SupabaseConfig.isConfigured, authStore.isSignedIn else { return }
        if !feedSessions.isEmpty || isLoadingFeed { return }
        await reloadCommunityFeed()
    }

    private func reloadCommunityFeed() async {
        guard SupabaseConfig.isConfigured, authStore.isSignedIn else { return }
        guard let client = supabase else {
            await MainActor.run {
                feedErrorMessage = "Unable to create Supabase client."
            }
            return
        }

        // Ensure date range is valid (by calendar day)
        if filterStartDate > filterEndDate {
            await MainActor.run {
                feedErrorMessage = "Start date must be before end date."
            }
            return
        }

        await MainActor.run {
            isLoadingFeed = true
            feedErrorMessage = nil
            hasMoreFeedPages = false
        }

        do {
            var query = client.database
                .from(SupabaseTables.tableGamePosts)
                .select()

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let startISO = isoFormatter.string(from: filterStartDate)
            let endISO = isoFormatter.string(from: filterEndDate)

            query = query
                .gte("created_at", value: startISO)
                .lte("created_at", value: endISO)

            let ordered = query.order("created_at", ascending: false)

            let items: [TableGamePostRow] = try await ordered
                .range(from: 0, to: communityPageSize - 1)
                .execute()
                .value

            let appLanguage = await MainActor.run { settingsStore.appLanguage }
            let anonymousLabel = L10n.tr("Anonymous", language: appLanguage)

            let gamesSet = Set(
                items.compactMap { row in
                    (row.game ?? row.session_details?.game)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )

            let locationsSet = Set(
                items.compactMap { row in
                    (row.location ?? row.session_details?.casino)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )

            let screenNamesSet = Set(
                items.flatMap { row -> [String] in
                    if let name = row.feedScreenName {
                        return [name]
                    }
                    return [anonymousLabel]
                }
            )

            await MainActor.run {
                feedSessions = items
                hasMoreFeedPages = items.count == communityPageSize
                availableGames = Array(gamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableLocations = Array(locationsSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableScreenNames = Array(screenNamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                selectedGames = selectedGames.intersection(gamesSet)
                selectedLocations = selectedLocations.intersection(locationsSet)
                selectedScreenNames = selectedScreenNames.intersection(screenNamesSet)
                reactionSummaries = [:]
                isLoadingFeed = false
            }
            await preloadLocationLookup(for: items)
            await refreshReactionSummaries(for: items)
        } catch {
            // Ignore benign cancellation errors (e.g. user navigating away mid-load)
            if (error as? CancellationError) != nil {
                await MainActor.run {
                    isLoadingFeed = false
                }
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                await MainActor.run {
                    isLoadingFeed = false
                }
                return
            }
            if let urlError = error as? URLError, urlError.code == .badURL {
                await MainActor.run {
                    feedErrorMessage = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
                    isLoadingFeed = false
                }
                return
            }
            await MainActor.run {
                feedErrorMessage = "Could not load community feed. Please try again."
                isLoadingFeed = false
            }
        }
    }

    private func loadMoreCommunityFeed() async {
        guard SupabaseConfig.isConfigured, authStore.isSignedIn else { return }
        guard let client = supabase else { return }
        guard !isLoadingFeed, hasMoreFeedPages else { return }

        // Ensure date range is still valid
        if filterStartDate > filterEndDate {
            await MainActor.run {
                feedErrorMessage = "Start date must be before end date."
            }
            return
        }

        await MainActor.run {
            isLoadingFeed = true
        }

        do {
            let existingItems: [TableGamePostRow] = await MainActor.run {
                feedSessions
            }

            var query = client.database
                .from(SupabaseTables.tableGamePosts)
                .select()

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let startISO = isoFormatter.string(from: filterStartDate)
            let endISO = isoFormatter.string(from: filterEndDate)

            query = query
                .gte("created_at", value: startISO)
                .lte("created_at", value: endISO)

            let ordered = query.order("created_at", ascending: false)

            let offset = existingItems.count
            let moreItems: [TableGamePostRow] = try await ordered
                .range(from: offset, to: offset + communityPageSize - 1)
                .execute()
                .value

            let allItems = existingItems + moreItems

            let appLanguage = await MainActor.run { settingsStore.appLanguage }
            let anonymousLabel = L10n.tr("Anonymous", language: appLanguage)

            let gamesSet = Set(
                allItems.compactMap { row in
                    (row.game ?? row.session_details?.game)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )

            let locationsSet = Set(
                allItems.compactMap { row in
                    (row.location ?? row.session_details?.casino)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )

            let screenNamesSet = Set(
                allItems.flatMap { row -> [String] in
                    if let name = row.feedScreenName {
                        return [name]
                    }
                    return [anonymousLabel]
                }
            )

            await MainActor.run {
                feedSessions = allItems
                hasMoreFeedPages = moreItems.count == communityPageSize
                availableGames = Array(gamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableLocations = Array(locationsSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableScreenNames = Array(screenNamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                selectedGames = selectedGames.intersection(gamesSet)
                selectedLocations = selectedLocations.intersection(locationsSet)
                selectedScreenNames = selectedScreenNames.intersection(screenNamesSet)
                isLoadingFeed = false
            }
            await preloadLocationLookup(for: allItems)
            await refreshReactionSummaries(for: moreItems)
        } catch {
            if (error as? CancellationError) != nil {
                await MainActor.run {
                    isLoadingFeed = false
                }
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                await MainActor.run {
                    isLoadingFeed = false
                }
                return
            }
            if let urlError = error as? URLError, urlError.code == .badURL {
                await MainActor.run {
                    feedErrorMessage = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
                    isLoadingFeed = false
                }
                return
            }
            await MainActor.run {
                feedErrorMessage = "Could not load more community sessions. Please try again."
                isLoadingFeed = false
            }
        }
    }

    private func preloadLocationLookup(for sessions: [TableGamePostRow]) async {
        guard SupabaseConfig.isConfigured, authStore.isSignedIn else { return }
        guard let client = supabase else { return }

        let uniqueNames = Set(
            sessions.compactMap { row in
                (row.location ?? row.session_details?.casino)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        )

        guard !uniqueNames.isEmpty else { return }

        await MainActor.run { isPreloadingLocationLookup = true }
        do {
            let data = try await client.database
                .from(SupabaseTables.casinoLocations)
                .select("name, latitude, longitude")
                .limit(500)
                .execute()
                .data

            struct LocationRow: Decodable {
                let name: String?
                let latitude: Double?
                let longitude: Double?
            }

            let decoded = try JSONDecoder().decode([LocationRow].self, from: data)

            var newLookup: [String: CLLocationCoordinate2D] = [:]

            for row in decoded {
                guard
                    let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                    uniqueNames.contains(name),
                    let lat = row.latitude,
                    let lon = row.longitude
                else {
                    continue
                }
                newLookup[name] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            await MainActor.run {
                for (name, coord) in newLookup {
                    locationLookup[name] = coord
                }
                isPreloadingLocationLookup = false
            }
        } catch {
            await MainActor.run { isPreloadingLocationLookup = false }
            // Silent failure; maps will simply have fewer or no pins.
        }
    }

}

struct CommunityFeedRow: View {
    let item: TableGamePostRow
    var reactionSummary: CommunityPostReactionSummary = .empty
    var canReact: Bool = false
    var isReactionBusy: Bool = false
    let onShowLocation: ((TableGamePostRow) -> Void)?
    var onOpenAuthor: (() -> Void)?
    var onReact: ((CommunityReactionType) -> Void)?
    var onReactBlocked: (() -> Void)?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    #if os(iOS)
    @State private var sharePreviewItem: ShareableImageItem?
    @State private var shareSheetItem: CommunityPostShareMediaItem?
    @State private var pendingShareImage: UIImage?
    @State private var pendingShareText: String?
    @State private var shouldPresentShareAfterPreviewDismiss = false
    @State private var isPreparingShare = false
    #endif

    private var isOwnPost: Bool {
        guard let postUserId = item.user_id,
              let currentUserId = authStore.session?.user.id else {
            return false
        }
        return postUserId == currentUserId
    }

    private var anonymousFeedLabel: String {
        L10n.tr("Anonymous", language: settingsStore.appLanguage)
    }

    private var metrics: TableGamePostMetrics? {
        item.metrics
    }

    private var currencySymbolForMetrics: String {
        metrics?.currency_symbol ?? settingsStore.currencySymbol
    }

    /// Full date/time for accessibility (always absolute).
    private var dateStringAccessibility: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.created_at)
    }

    private var relativeTimestamp: String {
        CommunityFeedFormatting.relativeTimestamp(from: item.created_at)
    }

    private var displayScreenName: String {
        item.feedScreenName ?? L10n.tr("Anonymous", language: settingsStore.appLanguage)
    }

    private var avatarURL: URL? {
        guard let path = item.feedAvatarPath else { return nil }
        return CommunityPostReactionsAPI.avatarPublicURL(path: path)
    }

    private var betDifferentialPercent: Double? {
        guard
            let rated = metrics?.avg_bet_rated,
            let actual = metrics?.avg_bet_actual,
            rated != 0
        else {
            return nil
        }
        return (Double(rated - actual) / Double(rated)) * 100.0
    }

    private var betDifferentialColor: Color {
        guard let diff = betDifferentialPercent else {
            return Color.white.opacity(0.1)
        }
        if diff > 0 {
            return Color.green.opacity(0.8)
        } else if diff < 0 {
            return Color.red.opacity(0.8)
        } else {
            return Color.gray.opacity(0.6)
        }
    }

    private var tiersPerHourColor: Color {
        guard let tiers = metrics?.tiers_per_hour else {
            return Color.white.opacity(0.12)
        }
        return tiers >= 0 ? Color.green.opacity(0.75) : Color.red.opacity(0.75)
    }

    private var tierDelta: Int? {
        guard
            let start = metrics?.starting_tier_points,
            let end = metrics?.ending_tier_points
        else {
            return nil
        }
        return end - start
    }

    private var tierDeltaColor: Color {
        guard let delta = tierDelta else {
            return Color.white.opacity(0.12)
        }
        if delta > 0 {
            return Color.green.opacity(0.75)
        } else if delta < 0 {
            return Color.red.opacity(0.75)
        } else {
            return Color.gray.opacity(0.6)
        }
    }

    var body: some View {
        let casinoName = item.location ?? item.session_details?.casino ?? "Unknown casino"
        let gameName = item.game ?? item.session_details?.game ?? "Unknown game"
        let metrics = self.metrics
        let comment = item.session_details?.comment?.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                communityAvatar

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayScreenName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(relativeTimestamp)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                            .accessibilityLabel("Posted \(dateStringAccessibility)")
                        Spacer(minLength: 0)
                    }

                    if let comment, !comment.isEmpty {
                        Text(comment)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(6)
                    }

                    HStack(spacing: 6) {
                        Text(casinoName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                        if let onShowLocation = onShowLocation {
                            Button {
                                onShowLocation(item)
                            } label: {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.green)
                            .accessibilityLabel("Show \(casinoName) on map")
                        }
                    }

                    Text(gameName)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(2)

                    CommunityFeedChipFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        if let wl = metrics?.net_win_loss {
                            let sym = currencySymbolForMetrics
                            Text(wl >= 0 ? "Net +\(sym)\(wl)" : "Net -\(sym)\(abs(wl))")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(wl >= 0 ? Color.green.opacity(0.75) : Color.red.opacity(0.75))
                                )
                                .accessibilityLabel("Net result \(wl >= 0 ? "plus" : "minus") \(abs(wl))")
                        }

                        if let tc = metrics?.total_comp, tc > 0, let ev = metrics?.expected_value {
                            let sym = currencySymbolForMetrics
                            Text(ev >= 0 ? "EV +\(sym)\(ev)" : "EV -\(sym)\(abs(ev))")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(ev >= 0 ? Color.teal.opacity(0.75) : Color.orange.opacity(0.75))
                                )
                                .accessibilityLabel("Expected value \(ev >= 0 ? "plus" : "minus") \(abs(ev)), including comps")
                        }

                        if let cc = metrics?.comp_count, cc > 0 {
                            let sym = currencySymbolForMetrics
                            let countLabel = cc == 1 ? "1 comp" : "\(cc) comps"
                            Group {
                                if let cv = metrics?.comp_value_total {
                                    Text("\(countLabel) · \(sym)\(cv) est.")
                                } else {
                                    Text(countLabel)
                                }
                            }
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.7))
                            )
                            .accessibilityLabel(
                                metrics?.comp_value_total.map { "\(cc) comps, estimated total value \(sym)\($0)" }
                                    ?? "\(cc) comps"
                            )
                        }

                        if let fp = metrics?.total_free_play, fp > 0 {
                            let sym = currencySymbolForMetrics
                            Text("Free play \(sym)\(fp)")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.8))
                                )
                                .accessibilityLabel("Free play total \(sym)\(fp)")
                        }

                        if let tiers = metrics?.tiers_per_hour {
                            Text(String(format: "%.1f pts/hr", tiers))
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(tiersPerHourColor)
                                )
                        }

                        if let diff = betDifferentialPercent {
                            Text("Rating Diff " + String(format: "%+.0f%%", diff))
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(betDifferentialColor)
                                )
                                .accessibilityLabel("Rating diff \(Int(diff)) percent")
                        } else if metrics?.avg_bet_actual != nil || metrics?.avg_bet_rated != nil {
                            L10nText("Rating Diff N/A")
                                .font(.caption.bold())
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }

                        if let delta = tierDelta {
                            let sign = delta >= 0 ? "+" : ""
                            Text("\(sign)\(delta) pts")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(tierDeltaColor)
                                )
                        } else if metrics?.tiers_per_hour == nil {
                            L10nText("PTS")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenAuthor?()
            }
            .accessibilityAddTraits(onOpenAuthor == nil ? [] : .isButton)
            .accessibilityHint(onOpenAuthor == nil ? "" : "Shows this member’s Community profile")

            reactionBar
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        #if os(iOS)
        .sheet(item: $sharePreviewItem, onDismiss: {
            guard shouldPresentShareAfterPreviewDismiss,
                  let image = pendingShareImage,
                  let text = pendingShareText else {
                pendingShareImage = nil
                pendingShareText = nil
                return
            }
            shouldPresentShareAfterPreviewDismiss = false
            pendingShareImage = nil
            pendingShareText = nil
            shareSheetItem = CommunityPostShareMediaItem(activityItems: [image, text])
        }) { preview in
            CommunityPostSharePreviewSheet(
                image: preview.image,
                caption: pendingShareText ?? "",
                gradient: settingsStore.primaryGradient,
                onShare: {
                    pendingShareImage = preview.image
                    shouldPresentShareAfterPreviewDismiss = true
                    sharePreviewItem = nil
                },
                onClose: {
                    shouldPresentShareAfterPreviewDismiss = false
                    pendingShareImage = nil
                    pendingShareText = nil
                    sharePreviewItem = nil
                }
            )
        }
        .sheet(item: $shareSheetItem) { item in
            ShareSheet(items: item.activityItems)
        }
        #endif
    }

    private var communityAvatar: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
            Image(systemName: item.feedScreenName == nil ? "eye.slash" : "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 22) {
            reactionButton(for: .heart)
            reactionButton(for: .like)
            reactionButton(for: .dislike)
            Spacer(minLength: 0)
            #if os(iOS)
            if isOwnPost {
                ownPostShareButton
            }
            #endif
        }
        .padding(.top, 2)
        .opacity(isReactionBusy ? 0.65 : 1)
    }

    #if os(iOS)
    private var ownPostShareButton: some View {
        Button {
            Task { await prepareAndPresentShare() }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
                .opacity(isPreparingShare ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShare)
        .accessibilityLabel("Share post")
        .accessibilityHint("Share this Community post to X, Instagram, and other apps")
    }

    @MainActor
    private func prepareAndPresentShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        let currency = currencySymbolForMetrics
        let caption = CommunityPostShareExporter.caption(
            for: item,
            currencySymbol: currency,
            anonymousLabel: anonymousFeedLabel
        )
        let avatar = await CommunityPostShareExporter.loadAvatarImage(from: avatarURL)
        guard let image = CommunityPostShareExporter.renderShareImage(
            item: item,
            currencySymbol: currency,
            gradient: settingsStore.primaryGradient,
            avatarImage: avatar,
            anonymousLabel: anonymousFeedLabel
        ) else {
            return
        }

        pendingShareText = caption
        pendingShareImage = image
        shareSheetItem = nil
        sharePreviewItem = ShareableImageItem(image: image)
    }
    #endif

    private func reactionButton(for type: CommunityReactionType) -> some View {
        let count = reactionSummary.count(for: type)
        let isActive = reactionSummary.viewerHas(type)
        let countLabel = CommunityFeedFormatting.compactCount(count)

        return Button {
            if canReact {
                onReact?(type)
            } else {
                onReactBlocked?()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isActive ? type.systemImageFilled : type.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(isActive ? reactionActiveColor(for: type) : Color.white.opacity(0.7))
                Text(countLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReactionBusy)
        .accessibilityLabel("\(type.accessibilityLabel), \(count)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(canReact ? "Double tap to toggle" : "Requires TierTap Pro")
    }

    private func reactionActiveColor(for type: CommunityReactionType) -> Color {
        switch type {
        case .heart: return Color.pink
        case .like: return Color.green
        case .dislike: return Color.orange
        }
    }
}

/// Author profile pushed from a Community feed row: header stats + that member’s posts.
struct CommunityAuthorProfileView: View {
    let author: CommunityAuthorRef
    let canReact: Bool
    let onShowLocation: ((TableGamePostRow) -> Void)?
    let onReactBlocked: (() -> Void)?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var posts: [TableGamePostRow] = []
    @State private var reactionSummaries: [Int64: CommunityPostReactionSummary] = [:]
    @State private var reactionInFlightPostIds: Set<Int64> = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMorePages = false
    @State private var nextFetchOffset = 0
    @State private var loadError: String?

    private var avatarURL: URL? {
        if let path = resolvedAvatarPath {
            return CommunityPostReactionsAPI.avatarPublicURL(path: path)
        }
        return nil
    }

    private var resolvedAvatarPath: String? {
        if let path = author.avatarPath, !path.isEmpty { return path }
        return posts.compactMap(\.feedAvatarPath).first
    }

    private var totalHearts: Int {
        posts.reduce(0) { $0 + (reactionSummaries[$1.id]?.heartCount ?? 0) }
    }

    private var totalLikes: Int {
        posts.reduce(0) { $0 + (reactionSummaries[$1.id]?.likeCount ?? 0) }
    }

    private var totalDislikes: Int {
        posts.reduce(0) { $0 + (reactionSummaries[$1.id]?.dislikeCount ?? 0) }
    }

    private var postCountLabel: String {
        if posts.isEmpty {
            return "Community posts"
        }
        if hasMorePages {
            return "\(posts.count)+ Community posts"
        }
        return posts.count == 1 ? "1 Community post" : "\(posts.count) Community posts"
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    authorHeader

                    if isLoading && posts.isEmpty {
                        ProgressView("Loading posts…")
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let loadError, posts.isEmpty {
                        Text(loadError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    } else if posts.isEmpty {
                        L10nText("No Community posts yet.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(posts) { item in
                                CommunityFeedRow(
                                    item: item,
                                    reactionSummary: reactionSummaries[item.id] ?? .empty,
                                    canReact: canReact,
                                    isReactionBusy: reactionInFlightPostIds.contains(item.id),
                                    onShowLocation: onShowLocation,
                                    onOpenAuthor: nil,
                                    onReact: { type in
                                        Task { await toggleReaction(postId: item.id, type: type) }
                                    },
                                    onReactBlocked: onReactBlocked
                                )
                                .environmentObject(settingsStore)
                                .environmentObject(authStore)
                            }

                            if let loadError {
                                Text(loadError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 4)
                            }

                            if hasMorePages {
                                Button {
                                    Task { await loadMoreAuthorPosts() }
                                } label: {
                                    HStack(spacing: 8) {
                                        if isLoadingMore {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                            L10nText("Load more")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(14)
                                    .padding(.top, 8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingMore)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(author.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: author.id) {
            await reloadAuthorPosts()
        }
    }

    private var authorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                authorAvatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(author.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text(postCountLabel)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                authorStatChip(
                    icon: "heart.fill",
                    tint: .pink,
                    label: "Hearts",
                    value: totalHearts
                )
                authorStatChip(
                    icon: "hand.thumbsup.fill",
                    tint: .green,
                    label: "Likes",
                    value: totalLikes
                )
                authorStatChip(
                    icon: "hand.thumbsdown.fill",
                    tint: .orange,
                    label: "Dislikes",
                    value: totalDislikes
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    private var authorAvatar: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        authorAvatarPlaceholder
                    }
                }
            } else {
                authorAvatarPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var authorAvatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Image(systemName: author.screenName == nil ? "eye.slash" : "person.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func authorStatChip(icon: String, tint: Color, label: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            Text(CommunityFeedFormatting.compactCount(value))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func reloadAuthorPosts() async {
        await MainActor.run {
            isLoading = true
            isLoadingMore = false
            hasMorePages = false
            nextFetchOffset = 0
            loadError = nil
            posts = []
            reactionSummaries = [:]
        }
        do {
            let page = try await CommunityAuthorPostsAPI.fetchPosts(
                for: author,
                offset: 0,
                limit: CommunityAuthorPostsAPI.pageSize
            )
            let viewerId = await MainActor.run { authStore.session?.user.id }
            let summaries = try await CommunityPostReactionsAPI.fetchSummaries(
                postIds: page.rows.map(\.id),
                viewerUserId: viewerId
            )
            await MainActor.run {
                posts = page.rows
                reactionSummaries = summaries
                nextFetchOffset = CommunityAuthorPostsAPI.pageSize
                hasMorePages = page.rawFetchedCount == CommunityAuthorPostsAPI.pageSize
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Could not load this member’s Community posts."
                isLoading = false
            }
        }
    }

    private func loadMoreAuthorPosts() async {
        let offset = await MainActor.run { nextFetchOffset }
        let canLoad = await MainActor.run { hasMorePages && !isLoading && !isLoadingMore }
        guard canLoad else { return }

        await MainActor.run {
            isLoadingMore = true
            loadError = nil
        }

        do {
            let page = try await CommunityAuthorPostsAPI.fetchPosts(
                for: author,
                offset: offset,
                limit: CommunityAuthorPostsAPI.pageSize
            )
            let viewerId = await MainActor.run { authStore.session?.user.id }
            let summaries = try await CommunityPostReactionsAPI.fetchSummaries(
                postIds: page.rows.map(\.id),
                viewerUserId: viewerId
            )
            await MainActor.run {
                let existingIds = Set(posts.map(\.id))
                let newRows = page.rows.filter { !existingIds.contains($0.id) }
                posts.append(contentsOf: newRows)
                for (id, summary) in summaries {
                    reactionSummaries[id] = summary
                }
                nextFetchOffset = offset + CommunityAuthorPostsAPI.pageSize
                hasMorePages = page.rawFetchedCount == CommunityAuthorPostsAPI.pageSize
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                loadError = "Could not load more posts. Please try again."
                isLoadingMore = false
            }
        }
    }

    private func toggleReaction(postId: Int64, type: CommunityReactionType) async {
        guard canReact else {
            await MainActor.run { onReactBlocked?() }
            return
        }
        guard let userId = await MainActor.run(body: { authStore.session?.user.id }) else {
            await MainActor.run { onReactBlocked?() }
            return
        }
        let alreadyBusy = await MainActor.run { reactionInFlightPostIds.contains(postId) }
        guard !alreadyBusy else { return }

        let prior = await MainActor.run { reactionSummaries[postId] ?? .empty }
        let currentlyActive = prior.viewerHas(type)
        let opposingActive: Bool = {
            switch type {
            case .like: return prior.viewerDisliked
            case .dislike: return prior.viewerLiked
            case .heart: return false
            }
        }()

        await MainActor.run {
            reactionInFlightPostIds.insert(postId)
            var next = prior
            next.applyOptimisticToggle(of: type)
            reactionSummaries[postId] = next
        }

        do {
            try await CommunityPostReactionsAPI.toggle(
                postId: postId,
                type: type,
                currentlyActive: currentlyActive,
                currentlyHasOpposingLikeDislike: opposingActive,
                userId: userId
            )
        } catch {
            await MainActor.run {
                reactionSummaries[postId] = prior
                loadError = "Could not update reaction. Please try again."
            }
        }

        await MainActor.run {
            reactionInFlightPostIds.remove(postId)
        }
    }
}

/// Wraps metric chips left-to-right and onto new rows to keep the community feed card short.
struct CommunityFeedChipFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CommunityFeedChipFlowLayout.computeFrames(
            maxWidth: proposal.width,
            subviews: subviews,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = CommunityFeedChipFlowLayout.computeFrames(
            maxWidth: proposal.width,
            subviews: subviews,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        for index in subviews.indices {
            guard index < result.frames.count else { continue }
            let frame = result.frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private static func computeFrames(
        maxWidth: CGFloat?,
        subviews: LayoutSubviews,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) -> (frames: [CGRect], size: CGSize) {
        guard !subviews.isEmpty else {
            return ([], .zero)
        }

        let containerW: CGFloat
        if let w = maxWidth, w.isFinite, w > 0 {
            containerW = w
        } else {
            var frames: [CGRect] = []
            var x: CGFloat = 0
            var maxH: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if size.width < 0.5 && size.height < 0.5 {
                    frames.append(.zero)
                    continue
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: 0), size: size))
                x += size.width + horizontalSpacing
                maxH = max(maxH, size.height)
            }
            let width = max(0, x - (subviews.isEmpty ? 0 : horizontalSpacing))
            return (frames, CGSize(width: width, height: maxH))
        }

        // Single pass: wrap at container width.
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if size.width < 0.5 && size.height < 0.5 {
                frames.append(.zero)
                continue
            }
            if x > 0, x + size.width > containerW {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            contentWidth = max(contentWidth, x + size.width)
            lineHeight = max(lineHeight, size.height)
            x += size.width + horizontalSpacing
        }

        let totalHeight = y + lineHeight
        let size = CGSize(width: min(containerW, contentWidth), height: totalHeight)
        return (frames, size)
    }
}

struct CommunityFeedFiltersView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var filterStartDate: Date
    @Binding var filterEndDate: Date
    @Binding var selectedGames: Set<String>
    @Binding var selectedLocations: Set<String>
    @Binding var selectedScreenNames: Set<String>
    @Binding var screenNameSearchText: String

    let availableGames: [String]
    let availableLocations: [String]
    let availableScreenNames: [String]
    let isLoading: Bool
    let onApply: () -> Void
    let onClear: () -> Void

    /// Single outer panel; expanded by default, collapses after Apply.
    @State private var isPanelExpanded = true

    private var filterSummary: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        var parts: [String] = [
            "\(formatter.string(from: filterStartDate)) – \(formatter.string(from: filterEndDate))"
        ]
        if !selectedGames.isEmpty {
            parts.append("\(selectedGames.count) game\(selectedGames.count == 1 ? "" : "s")")
        }
        if !selectedLocations.isEmpty {
            parts.append("\(selectedLocations.count) location\(selectedLocations.count == 1 ? "" : "s")")
        }
        if !selectedScreenNames.isEmpty {
            parts.append("\(selectedScreenNames.count) screen name\(selectedScreenNames.count == 1 ? "" : "s")")
        }
        let trimmedSearch = screenNameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            parts.append("“\(trimmedSearch)”")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPanelExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    LocalizedLabel(title: "Filters", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 8)
                    if !isPanelExpanded {
                        Text(filterSummary)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Image(systemName: isPanelExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if isPanelExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        FilterPanelPillButton(title: "Clear Filter") {
                            onClear()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPanelExpanded = true
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedLabel(title: "Date & time range", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))

                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                L10nText("From")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker(
                                    "",
                                    selection: $filterStartDate.datePortion(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                                DatePicker(
                                    "",
                                    selection: $filterStartDate.timePortion(),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Rectangle()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 1)
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                L10nText("To")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                DatePicker(
                                    "",
                                    selection: $filterEndDate.datePortion(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                                DatePicker(
                                    "",
                                    selection: $filterEndDate.timePortion(),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.white)
                                .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !availableGames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                LocalizedLabel(title: "Games", systemImage: "suit.club.fill")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if !selectedGames.isEmpty {
                                    Text("\(selectedGames.count) selected")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableGames, id: \.self) { game in
                                        let isSelected = selectedGames.contains(game)
                                        Button {
                                            if isSelected {
                                                selectedGames.remove(game)
                                            } else {
                                                selectedGames.insert(game)
                                            }
                                        } label: {
                                            Text(game)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.green : Color.white.opacity(0.18))
                                                .foregroundColor(isSelected ? .black : .white)
                                                .cornerRadius(16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if !availableLocations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                LocalizedLabel(title: "Locations", systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if !selectedLocations.isEmpty {
                                    Text("\(selectedLocations.count) selected")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableLocations, id: \.self) { location in
                                        let isSelected = selectedLocations.contains(location)
                                        Button {
                                            if isSelected {
                                                selectedLocations.remove(location)
                                            } else {
                                                selectedLocations.insert(location)
                                            }
                                        } label: {
                                            Text(location)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.green : Color.white.opacity(0.18))
                                                .foregroundColor(isSelected ? .black : .white)
                                                .cornerRadius(16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            LocalizedLabel(title: "Screen names", systemImage: "person.text.rectangle")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            if !selectedScreenNames.isEmpty {
                                Text("\(selectedScreenNames.count) selected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }

                        LocalizedLabel(title: "Search by screen name", systemImage: "magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                            .labelStyle(.titleAndIcon)

                        TextField(
                            L10n.tr("Type a screen name", language: appLanguage),
                            text: $screenNameSearchText
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                        .foregroundColor(.white)

                        if !availableScreenNames.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableScreenNames, id: \.self) { name in
                                        let isSelected = selectedScreenNames.contains(name)
                                        Button {
                                            if isSelected {
                                                selectedScreenNames.remove(name)
                                            } else {
                                                selectedScreenNames.insert(name)
                                            }
                                        } label: {
                                            Text(name)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.green : Color.white.opacity(0.18))
                                                .foregroundColor(isSelected ? .black : .white)
                                                .cornerRadius(16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        onApply()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPanelExpanded = false
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.green)
                            } else {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                L10nText("Apply Filters")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.28))
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading)
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.12))
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Community feed map

struct CommunityMapLocation: Identifiable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    var id: String { name }
}

struct CommunityFeedMapSheet: View {
    let sessions: [TableGamePostRow]
    let locationLookup: [String: CLLocationCoordinate2D]
    let isLocationLookupLoading: Bool

    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    )

    private var sessionCasinoNames: Set<String> {
        Set(
            sessions.compactMap { row in
                (row.location ?? row.session_details?.casino)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        )
    }

    /// Pins are always derived from the latest `locationLookup` (no stale `@State` cache).
    private var resolvedMapLocations: [CommunityMapLocation] {
        let uniqueNames = Set(
            sessions.compactMap { row in
                (row.location ?? row.session_details?.casino)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        )
        return uniqueNames.compactMap { name in
            guard let coord = locationLookup[name] else { return nil }
            return CommunityMapLocation(name: name, coordinate: coord)
        }
    }

    /// Drives `region` updates when lookup data arrives or sessions change.
    private var mapRefreshKey: String {
        let sorted = Array(sessionCasinoNames).sorted().joined(separator: "|")
        let matched = sessionCasinoNames.filter { locationLookup[$0] != nil }.count
        return "\(locationLookup.count)-\(matched)-\(sorted)-\(isLocationLookupLoading)"
    }

    private var showLoadingPlaceholder: Bool {
        isLocationLookupLoading && !sessionCasinoNames.isEmpty && resolvedMapLocations.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()

                if resolvedMapLocations.isEmpty {
                    Group {
                        if showLoadingPlaceholder {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(.white)
                                L10nText("Loading casino locations…")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        } else if sessionCasinoNames.isEmpty {
                            L10nText("No casino locations in these sessions.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding()
                        } else {
                            L10nText("No mapped casino locations for this feed yet.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                } else {
                    Map(coordinateRegion: $region, annotationItems: resolvedMapLocations) { loc in
                        MapAnnotation(coordinate: loc.coordinate) {
                            VStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.red)
                                Text(loc.name)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .localizedNavigationTitle("Session Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
            .onChange(of: mapRefreshKey) { _ in
                updateRegion(for: resolvedMapLocations)
            }
            .onAppear {
                updateRegion(for: resolvedMapLocations)
            }
        }
    }

    private func updateRegion(for locations: [CommunityMapLocation]) {
        guard !locations.isEmpty else { return }
        let lats = locations.map { $0.coordinate.latitude }
        let lons = locations.map { $0.coordinate.longitude }

        guard
            let minLat = lats.min(),
            let maxLat = lats.max(),
            let minLon = lons.min(),
            let maxLon = lons.max()
        else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.5, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.5, (maxLon - minLon) * 1.5)
        )

        region = MKCoordinateRegion(center: center, span: span)
    }
}


// MARK: - Community publish selection

enum CommunityPublishResult {
    case success(Int)
    case failure(Error)
}

struct CommunitySessionPublishSelectionView: View {
    let sessions: [Session]
    /// When set (e.g. embedded in post-closeout flow), toolbar leading goes **Back** to this handler instead of dismissing the sheet.
    let onBackFromSelection: (() -> Void)?
    let onFinished: (CommunityPublishResult) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSessionIDs: Set<UUID>
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var postComment: String = ""
    /// When on, `tiers_per_hour` is stored in metrics and shown on the feed.
    @State private var publishTierPerHour = true
    /// When on, buy-in, cash-out, and net win/loss are stored in metrics and shown on the feed.
    @State private var publishWinLoss = false
    /// When on, comp count and total estimated comp value (from logged comps) are stored and shown on the feed.
    @State private var publishCompDetails = false
    /// When on, total logged free play is stored in metrics and shown on the feed (promotional value, not cash P&L).
    @State private var publishFreePlayTotal = true
    /// When on, your Community screen name is stored on each post; when off, posts show as Anonymous.
    @State private var attachScreenName = true
    /// When on, upload and stamp `avatar_path` so the feed shows your photo (opt-in).
    @State private var attachProfilePhoto = false
    @State private var profilePhotoSource: CommunityProfilePhotoShareSource = .tierTap

    init(
        sessions: [Session],
        initialSelectedSessionIDs: Set<UUID>? = nil,
        onBackFromSelection: (() -> Void)? = nil,
        onFinished: @escaping (CommunityPublishResult) -> Void
    ) {
        self.sessions = sessions
        self.onBackFromSelection = onBackFromSelection
        self.onFinished = onFinished
        _selectedSessionIDs = State(initialValue: initialSelectedSessionIDs ?? [])
    }

    private var sortedSessions: [Session] {
        sessions.sorted { $0.startTime > $1.startTime }
    }

    private var availableProfilePhotoSources: [CommunityProfilePhotoShareSource] {
        var sources: [CommunityProfilePhotoShareSource] = []
        if authStore.hasLocalProfilePhoto { sources.append(.tierTap) }
        if authStore.hasOAuthAccountProfilePhoto { sources.append(.signInAccount) }
        return sources
    }

    /// Approximate row height for `CommunitySessionSelectableRow` at default text size (2 lines + padding). List shows `sessionListVisibleRowCount` rows tall.
    private static let sessionListRowHeight: CGFloat = 58
    private static let sessionListVisibleRowCount: CGFloat = 3

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        L10nText("No completed sessions available to publish.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        Section(
                            header: L10nText("Add a short comment (optional)").foregroundColor(.gray),
                            footer: Text("One line in the feed. \(postComment.count)/\(ProfanityChecker.maxCommentLength) characters")
                                .foregroundColor(.gray.opacity(0.8))
                        ) {
                            TextField("e.g. Great run today", text: $postComment)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.sentences)
                                .onChange(of: postComment) { newValue in
                                    if newValue.count > ProfanityChecker.maxCommentLength {
                                        postComment = String(newValue.prefix(ProfanityChecker.maxCommentLength))
                                    }
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                        }

                        Section(
                            header: L10nText("Privacy").foregroundColor(.secondary),
                            footer: L10nText("Screen name and photo are optional. When photo sharing is off, the feed shows a placeholder. Existing posts without a photo keep working.")
                                .foregroundColor(.gray.opacity(0.8))
                        ) {
                            Toggle(isOn: $attachScreenName) {
                                L10nText("Show my screen name")
                                    .foregroundColor(.white)
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $attachProfilePhoto) {
                                VStack(alignment: .leading, spacing: 2) {
                                    L10nText("Share profile photo")
                                        .foregroundColor(.white)
                                    L10nText(
                                        authStore.hasAnyShareableProfilePhoto
                                        ? "Shown next to your posts in the feed"
                                        : "Set a photo in Account, or sign in with Google"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                }
                            }
                            .tint(.green)
                            .disabled(!authStore.hasAnyShareableProfilePhoto)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            if attachProfilePhoto, !availableProfilePhotoSources.isEmpty {
                                if availableProfilePhotoSources.count > 1 {
                                    Picker(selection: $profilePhotoSource) {
                                        ForEach(availableProfilePhotoSources) { source in
                                            Text(source.title).tag(source)
                                        }
                                    } label: {
                                        L10nText("Photo to share")
                                            .foregroundColor(.white)
                                    }
                                    .tint(.green)
                                    .listRowBackground(Color(.systemGray6).opacity(0.15))
                                }

                                HStack(spacing: 12) {
                                    communityPublishPhotoPreview(for: resolvedProfilePhotoSource)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resolvedProfilePhotoSource.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white)
                                        L10nText("Preview of what Community will show")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                            }
                        }

                        Section(
                            header: L10nText("Share details").foregroundColor(.secondary),
                            footer: L10nText("Tier/hour, free play, comps, and wins/losses are optional.")
                                .foregroundColor(.gray.opacity(0.8))
                        ) {
                            Toggle(isOn: $publishTierPerHour) {
                                L10nText("Tier / hour")
                                    .foregroundColor(.white)
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $publishFreePlayTotal) {
                                VStack(alignment: .leading, spacing: 2) {
                                    L10nText("Free play total")
                                        .foregroundColor(.white)
                                    L10nText("Promotional value; not cash win/loss")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $publishCompDetails) {
                                VStack(alignment: .leading, spacing: 2) {
                                    L10nText("Comp details")
                                        .foregroundColor(.white)
                                    L10nText("Count and total estimated value")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))

                            Toggle(isOn: $publishWinLoss) {
                                L10nText("Publish wins / losses")
                                    .foregroundColor(.white)
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                        }

                        Section(header: L10nText("Choose sessions to publish").foregroundColor(.primary)) {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                                        CommunitySessionSelectableRow(
                                            session: session,
                                            isSelected: selectedSessionIDs.contains(session.id)
                                        ) {
                                            toggleSelection(for: session)
                                        }
                                        if index < sortedSessions.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.12))
                                        }
                                    }
                                }
                            }
                            .frame(height: Self.sessionListRowHeight * Self.sessionListVisibleRowCount)
                            .scrollIndicators(.visible)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .localizedNavigationTitle("Pick Sessions To Publish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { syncProfilePhotoShareDefaults() }
            .onChange(of: authStore.localProfilePhoto) { _ in
                syncProfilePhotoShareDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onBackFromSelection {
                        Button("Back") {
                            onBackFromSelection()
                        }
                        .foregroundColor(.green)
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.green)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let message = errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.black.opacity(0.6))
                    }
                    if !sessions.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                selectedSessionIDs = Set(sessions.map { $0.id })
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    L10nText("Select All Sessions")
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                        .multilineTextAlignment(.center)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 6)
                                .background(settingsStore.primaryGradient)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedSessionIDs.removeAll()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    L10nText("Clear All")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 6)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.28, blue: 0.26),
                                            Color(red: 0.52, green: 0.1, blue: 0.14)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)

                        Button {
                            Task { await publishSelectedSessions() }
                        } label: {
                            Group {
                                if isPublishing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    L10nText("Publish")
                                        .fontWeight(.semibold)
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedSessionIDs.isEmpty || isPublishing)
                        .opacity(selectedSessionIDs.isEmpty && !isPublishing ? 0.5 : 1)
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    settingsStore.primaryGradient
                        .opacity(0.95)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    private func toggleSelection(for session: Session) {
        if selectedSessionIDs.contains(session.id) {
            selectedSessionIDs.remove(session.id)
        } else {
            selectedSessionIDs.insert(session.id)
        }
    }

    private var resolvedProfilePhotoSource: CommunityProfilePhotoShareSource {
        let available = availableProfilePhotoSources
        if available.contains(profilePhotoSource) {
            return profilePhotoSource
        }
        return available.first ?? .tierTap
    }

    @ViewBuilder
    private func communityPublishPhotoPreview(for source: CommunityProfilePhotoShareSource) -> some View {
        Group {
            switch source {
            case .tierTap:
                if let image = authStore.localProfilePhotoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    profilePhotoPreviewPlaceholder
                }
            case .signInAccount:
                if let url = authStore.oauthAccountProfilePhotoURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            profilePhotoPreviewPlaceholder
                        }
                    }
                } else {
                    profilePhotoPreviewPlaceholder
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var profilePhotoPreviewPlaceholder: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func syncProfilePhotoShareDefaults() {
        let available = availableProfilePhotoSources
        if !available.contains(profilePhotoSource) {
            profilePhotoSource = available.first ?? .tierTap
        }
        if !authStore.hasAnyShareableProfilePhoto {
            attachProfilePhoto = false
        }
    }

    private func publishSelectedSessions() async {
        guard !selectedSessionIDs.isEmpty else { return }
        guard SupabaseConfig.isConfigured else {
            await MainActor.run {
                errorMessage = "Supabase is not configured. Add your project keys to SupabaseKeys.plist."
            }
            return
        }
        guard authStore.isSignedIn, let _ = authStore.session else {
            await MainActor.run {
                errorMessage = "You need to be signed in to publish sessions."
            }
            return
        }

        let chosen = sortedSessions.filter { selectedSessionIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }

        let trimmedComment = postComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = ProfanityChecker.replaceProfanity(trimmedComment)
        let commentToPublish = sanitized.isEmpty ? nil : String(sanitized.prefix(ProfanityChecker.maxCommentLength))

        await MainActor.run {
            isPublishing = true
            errorMessage = nil
        }

        do {
            let publishedCount = try await CommunityPublisher.publishSessions(
                chosen,
                authStore: authStore,
                currencyCode: settingsStore.currencyCode,
                currencySymbol: settingsStore.currencySymbol,
                comment: commentToPublish,
                publishTierPerHour: publishTierPerHour,
                publishWinLoss: publishWinLoss,
                publishCompDetails: publishCompDetails,
                publishFreePlayTotal: publishFreePlayTotal,
                attachScreenName: attachScreenName,
                attachProfilePhoto: attachProfilePhoto && authStore.hasAnyShareableProfilePhoto,
                profilePhotoSource: resolvedProfilePhotoSource
            )
            await MainActor.run {
                isPublishing = false
                store.markSessionsPublished(selectedSessionIDs)
                onFinished(.success(publishedCount))
                dismiss()
            }
        } catch {
            let message: String
            if let urlError = error as? URLError, urlError.code == .badURL {
                message = "Invalid URL (common in Simulator). Check SupabaseKeys.plist has a valid https URL."
            } else {
                message = error.localizedDescription
            }
            await MainActor.run {
                isPublishing = false
                errorMessage = message
                onFinished(.failure(error))
            }
        }
    }
}

private struct CommunitySessionSelectableRow: View {
    let session: Session
    let isSelected: Bool
    let onToggle: () -> Void

    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.casino)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        if let wl = session.winLoss {
                            Text(wl >= 0 ? "+\(settingsStore.currencySymbol)\(wl)" : "-\(settingsStore.currencySymbol)\(abs(wl))")
                                .font(.caption.bold())
                                .foregroundColor(wl >= 0 ? .green : .red)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session.game)
                            .font(.caption)
                            .foregroundColor(.gray)
                        L10nText("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(session.startTime, style: .date)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(session.startTime, style: .time)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}


