import SwiftUI
import MapKit
import UIKit

enum MainTab: Hashable {
    case sessions
    case history
    case trips
    case analytics
    case community
    case settings
}

struct RootTabView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var selectedTab: MainTab = .sessions
    @State private var showGASupportFromMoodDownswing = false

    var body: some View {
        TabView(selection: $selectedTab) {
            AnalyticsView()
                .tabItem {
                    LocalizedLabel(title: "Analytics", systemImage: "chart.pie.fill")
                }
                .tag(MainTab.analytics)

            TripsView()
                .tabItem {
                    LocalizedLabel(title: "Trips", systemImage: "suitcase.fill")
                }
                .tag(MainTab.trips)

            HomeView()
                .tabItem {
                    LocalizedLabel(title: "Sessions", systemImage: "play.circle.fill")
                }
                .tag(MainTab.sessions)

            CommunitySessionsView()
                .id(authStore.isSignedIn)
                .tabItem {
                    LocalizedLabel(title: "Community", systemImage: "person.3.sequence.fill")
                }
                .tag(MainTab.community)

            SettingsView()
                .tabItem {
                    LocalizedLabel(title: "Settings", systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
        }
        .tint(settingsStore.primaryColor)
        .onReceive(NotificationCenter.default.publisher(for: .sessionMoodDownswingNeedsGASupport)) { _ in
            showGASupportFromMoodDownswing = true
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
}

struct CommunitySessionsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @State private var showAuthSheet = false
    @State private var emailInput = ""
    @State private var isPublishSelectorPresented = false
    @State private var publishStatusMessage: String?
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

    private var hasProAccess: Bool {
        subscriptionStore.isPro || settingsStore.isSubscriptionOverrideActive
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
            if !hasProAccess || !authStore.isSignedIn {
                TierTapPaywallView()
                    .environmentObject(subscriptionStore)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
            } else {
                ZStack {
                    settingsStore.primaryGradient.ignoresSafeArea()
                    ScrollView {
                    VStack(spacing: 16) {

                        if let error = feedErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Filters
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
                                L10nText("Be the first to publish your sessions using the button at the bottom.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 32)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleFeedSessions) { item in
                                    CommunityFeedRow(item: item, onShowLocation: { row in
                                        presentCommunityMap(with: [row])
                                    })
                                        .environmentObject(settingsStore)
                                        .padding(.horizontal)
                                }

                                if hasMoreFeedPages {
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
                    .padding(.bottom, 24)
                    }
                    .refreshable {
                        await reloadCommunityFeed()
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
            .adaptiveSheet(isPresented: $showAuthSheet) {
                CommunityAuthSheet(
                    emailInput: $emailInput,
                    onDismiss: { showAuthSheet = false }
                )
                .environmentObject(authStore)
                .environmentObject(settingsStore)
                .environmentObject(subscriptionStore)
            }
            .safeAreaInset(edge: .bottom) {
                if SupabaseConfig.isConfigured,
                   authStore.isSignedIn,
                   !sessionStore.sessions.isEmpty {
                    VStack(spacing: 8) {
                        if let message = publishStatusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        } else if let error = publishErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }
                        Button {
                            isPublishSelectorPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.circle.fill")
                                L10nText("Pick Sessions To Publish")
                                    .fontWeight(.semibold)
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(settingsStore.primaryGradient)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
            .adaptiveSheet(isPresented: $isPublishSelectorPresented) {
                CommunitySessionPublishSelectionView(
                    sessions: sessionStore.sessions.filter { $0.isComplete }
                ) { result in
                    switch result {
                    case .success(let count):
                        publishErrorMessage = nil
                        publishStatusMessage = count == 1 ?
                            "Published 1 session to the community." :
                            "Published \(count) sessions to the community."
                    case .failure(let error):
                        publishStatusMessage = nil
                        publishErrorMessage = error.localizedDescription
                    }
                }
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
    @State private var profileSaved = false
    @State private var isShowingCameraPicker = false
    @State private var isShowingLibraryPicker = false
    @State private var showSubscriptionPaywall = false

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
        default:
            return L10n.tr("TierTap Pro", language: appLanguage)
        }
    }

    private var subscriptionAccessRow: some View {
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
            Button {
                showSubscriptionPaywall = true
            } label: {
                L10nText(hasProAccess ? "Manage" : "Subscribe")
                    .font(.caption2.weight(.bold))
                    .underline()
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
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

            if profileSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    L10nText("Saved")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func saveProfile() {
        profileSaved = false
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
                } else {
                    try? authStore.deleteLocalProfilePhoto()
                }
            }
            await MainActor.run {
                isSavingProfile = false
                if authStore.errorMessage == nil {
                    profileSaved = true
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

                Button("Log out", role: .destructive) {
                    authStore.signOut()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    L10nText("Why create an account?")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedLabel(title: "Advanced AI summaries and guidance for your sessions.", systemImage: "wand.and.stars")
                        LocalizedLabel(title: "Sync your sessions and bankroll safely across devices.", systemImage: "icloud")
                        LocalizedLabel(title: "See and publish Community sessions with other players.", systemImage: "person.3.sequence.fill")
                        LocalizedLabel(title: "Back up your data so you never lose your history.", systemImage: "clock.arrow.circlepath")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .labelStyle(.titleAndIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.black.opacity(0.35))
                .cornerRadius(14)

                Button {
                    authStore.signInWithApple()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                        L10nText("Sign in with Apple")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.black)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(authStore.isLoading)

                Button {
                    authStore.signInWithGoogle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        L10nText("Sign in with Google")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(authStore.isLoading)

                VStack(alignment: .leading, spacing: 6) {
                    L10nText("Email")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    L10nText("We'll email a one-time sign-in link — no password.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("you@example.com", text: $emailInput)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .font(.subheadline)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                        .foregroundColor(.white)

                    if let info = authStore.infoMessage {
                        Text(info)
                            .font(.caption)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.leading)
                    }

                    if let msg = authStore.errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }

                    Button {
                        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await authStore.signInWithOTP(email: trimmedEmail) }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(authStore.otpSent ? "Magic link sent" : "Send magic link")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        authStore.isLoading ||
                        emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if authStore.otpSent {
                        L10nText("Open the link in the email on this device to finish signing in. You can leave this screen open or close it.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)
                            .minimumScaleFactor(0.85)
                    }
                }

                Button {
                    onDismiss()
                } label: {
                    L10nText("Continue without an account")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                L10nText("You can continue using TierTap without signing in. For advanced AI features and Community sessions, you’ll need to create and log in to your account.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)
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
    private var communityPageSize: Int { 100 }

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
                isLoadingFeed = false
            }
            await preloadLocationLookup(for: items)
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
    let onShowLocation: ((TableGamePostRow) -> Void)?

    @EnvironmentObject private var settingsStore: SettingsStore

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

    /// Shown in the card corner: Today/Yesterday + time, or medium date + short time.
    private var feedDateDisplay: String {
        let date = item.created_at
        let cal = Calendar.current
        let timeOnly = DateFormatter()
        timeOnly.timeStyle = .short
        timeOnly.dateStyle = .none
        let timeStr = timeOnly.string(from: date)

        if cal.isDateInToday(date) {
            return "Today, \(timeStr)"
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday, \(timeStr)"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(casinoName)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(2)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)

                    if let screenName = item.feedScreenName {
                        HStack(spacing: 4) {
                            Image(systemName: "person.text.rectangle")
                                .font(.caption2)
                            Text(screenName)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .accessibilityLabel("Screen Name \(screenName)")
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash")
                                .font(.caption2)
                            L10nText("Anonymous")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .accessibilityLabel(L10n.tr("Anonymous", language: settingsStore.appLanguage))
                    }

                    if let comment = item.session_details?.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(feedDateDisplay)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel("Posted \(dateStringAccessibility)")
            }

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
        .padding(12)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Wraps metric chips left-to-right and onto new rows to keep the community feed card short.
private struct CommunityFeedChipFlowLayout: Layout {
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
    let onFinished: (CommunityPublishResult) -> Void

    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var postComment: String = ""
    /// When on, `tiers_per_hour` is stored in metrics and shown on the feed.
    @State private var publishTierPerHour = true
    /// When on, buy-in, cash-out, and net win/loss are stored in metrics and shown on the feed.
    @State private var publishWinLoss = false
    /// When on, comp count and total estimated comp value (from logged comps) are stored and shown on the feed.
    @State private var publishCompDetails = false
    /// When on, your Community screen name is stored on each post; when off, posts show as Anonymous.
    @State private var attachScreenName = true

    private var sortedSessions: [Session] {
        sessions.sorted { $0.startTime > $1.startTime }
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
                            footer: L10nText("When off, posts appear as Anonymous in the feed.")
                                .foregroundColor(.gray.opacity(0.8))
                        ) {
                            Toggle(isOn: $attachScreenName) {
                                L10nText("Show my screen name")
                                    .foregroundColor(.white)
                            }
                            .tint(.green)
                            .listRowBackground(Color(.systemGray6).opacity(0.15))
                        }

                        Section(
                            header: L10nText("Share details").foregroundColor(.secondary),
                            footer: L10nText("Tier/hour, comps, and wins/losses are optional.")
                                .foregroundColor(.gray.opacity(0.8))
                        ) {
                            Toggle(isOn: $publishTierPerHour) {
                                L10nText("Tier / hour")
                                    .foregroundColor(.white)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.green)
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
                attachScreenName: attachScreenName
            )
            await MainActor.run {
                isPublishing = false
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


