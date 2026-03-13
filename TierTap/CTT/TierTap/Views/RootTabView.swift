import SwiftUI
import MapKit
import UIKit

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
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
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
                .id(authStore.isSignedIn)
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
    @State private var isLoadingFeed = false
    @State private var feedErrorMessage: String?
    @State private var availableGames: [String] = []
    @State private var availableLocations: [String] = []
    @State private var filterStartDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-24 * 60 * 60)
    @State private var filterEndDate: Date = Date()
    @State private var showMapSheet = false
    @State private var mapSessions: [TableGamePostRow] = []
    @State private var hasMoreFeedPages = false

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

            return matchesGame && matchesLocation
        }
    }

    var body: some View {
        NavigationStack {
            if !subscriptionStore.isPro || !authStore.isSignedIn {
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
                            availableGames: availableGames,
                            availableLocations: availableLocations,
                            isLoading: isLoadingFeed,
                            onApply: {
                                Task { await reloadCommunityFeed() }
                            },
                            onClear: {
                                filterStartDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-24 * 60 * 60)
                                filterEndDate = Date()
                                selectedGames.removeAll()
                                selectedLocations.removeAll()
                                Task { await reloadCommunityFeed() }
                            }
                        )

                        if !SupabaseConfig.isConfigured {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("Connect Supabase to see the community feed.")
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
                                Text("Sign in to view the community feed.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Text("Use the Account button in the top right to sign in.")
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
                                Text("No community sessions have been published yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Text("Be the first to publish your sessions using the button at the bottom.")
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
                                        mapSessions = [row]
                                        showMapSheet = true
                                    })
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
                                                Text("Load more")
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
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if SupabaseConfig.isConfigured, authStore.isSignedIn, !visibleFeedSessions.isEmpty {
                        Button {
                            mapSessions = visibleFeedSessions
                            showMapSheet = true
                        } label: {
                            Text("🌐")
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
                               let data = authStore.userProfilePhotoData,
                               let uiImage = UIImage(data: data) {
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
                                if authStore.userProfilePhotoData == nil,
                                   let emojis = authStore.userProfileEmojis,
                                   !emojis.isEmpty {
                                    Text(emojis)
                                        .font(.caption)
                                }
                                Text(authStore.signedInSummary ?? authStore.userEmail ?? "Account")
                                    .lineLimit(1)
                                    .font(.caption)
                            } else {
                                Text("Account")
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
            .sheet(isPresented: $showAuthSheet) {
                CommunityAuthSheet(
                    emailInput: $emailInput,
                    onDismiss: { showAuthSheet = false }
                )
                .environmentObject(authStore)
                .environmentObject(settingsStore)
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
                                Text("Publish Sessions")
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
            .sheet(isPresented: $isPublishSelectorPresented) {
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
            .sheet(isPresented: $showMapSheet) {
                CommunityFeedMapSheet(
                    sessions: mapSessions
                )
                .environmentObject(settingsStore)
                .environmentObject(authStore)
            }
            }
        }
    }
}

// MARK: - Account / auth sheet (login info + options)
struct CommunityAuthSheet: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var emailInput: String
    var onDismiss: () -> Void

    private enum EmailAuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .signUp: return "Sign up"
            }
        }

        var buttonTitle: String {
            switch self {
            case .signIn: return "Sign in with email"
            case .signUp: return "Create email account"
            }
        }
    }

    @State private var profileDisplayName: String = ""
    @State private var profileEmojis: String = ""
    @State private var profilePhoto: UIImage?
    @State private var isSavingProfile = false
    @State private var profileSaved = false
    @State private var isShowingCameraPicker = false
    @State private var isShowingLibraryPicker = false
    @State private var emailAuthMode: EmailAuthMode = .signUp
    @State private var emailPassword: String = ""
    @State private var emailPasswordConfirm: String = ""

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
                        .padding(20)
                }
            }
            .navigationTitle("Account")
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
            if let data = authStore.userProfilePhotoData {
                profilePhoto = UIImage(data: data)
            }
        }
        .onChange(of: authStore.session?.user.id) { _ in
            profileDisplayName = authStore.userDisplayName ?? ""
            profileEmojis = authStore.userProfileEmojis ?? ""
            if let data = authStore.userProfilePhotoData {
                profilePhoto = UIImage(data: data)
            } else {
                profilePhoto = nil
            }
        }
        .onChange(of: profilePhoto) { _ in
            if authStore.isSignedIn {
                saveProfile()
            }
        }
        .sheet(isPresented: $isShowingCameraPicker) {
            ProfilePhotoCaptureView(image: $profilePhoto, preferredSourceType: .camera)
        }
        .sheet(isPresented: $isShowingLibraryPicker) {
            ProfilePhotoCaptureView(image: $profilePhoto, preferredSourceType: .photoLibrary)
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile")
                .font(.title2.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ZStack {
                        if let image = profilePhoto {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if let emojis = authStore.userProfileEmojis, !emojis.isEmpty {
                            Text(emojis)
                                .font(.system(size: 40))
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 40))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            isShowingCameraPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                Text("Take photo")
                                    .font(.subheadline.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        Button {
                            isShowingLibraryPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                Text("Choose from library")
                                    .font(.subheadline.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Display name")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))
                TextField("Your name", text: $profileDisplayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .cornerRadius(16)

            if profileSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func saveProfile() {
        profileSaved = false
        isSavingProfile = true
        Task {
            var photoBase64: String?
            if let image = profilePhoto,
               let data = image.jpegData(compressionQuality: 0.8) {
                photoBase64 = data.base64EncodedString()
            }
            await authStore.updateProfile(
                displayName: profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                emojis: profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines),
                photoBase64: photoBase64
            )
            await MainActor.run {
                isSavingProfile = false
                profileSaved = true
            }
        }
    }

    @ViewBuilder
    private var authContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 120)
                    .shadow(radius: 10)

                Text("Your TierTap Account")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Sign in to unlock advanced AI features, sync your data, and join Community sessions.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 4)

            if !SupabaseConfig.isConfigured {
                Text("Add SUPABASE_URL and SUPABASE_ANON_KEY to SupabaseKeys.plist to enable sign-in. You can still use TierTap without an account.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if authStore.isSignedIn {
                // Profile: display name & emojis (large section)
                profileSection

                // Current login info moved below profile in its own bubble
                VStack {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(settingsStore.primaryGradient)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in")
                                .font(.headline)
                                .foregroundColor(.white)
                            if let name = authStore.userDisplayName, !name.isEmpty {
                                Text(name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                            }
                            if let email = authStore.userEmail {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            if let emojis = authStore.userProfileEmojis, !emojis.isEmpty {
                                Text(emojis)
                                    .font(.title3)
                            }
                        }
                        Spacer()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6).opacity(0.18))
                .cornerRadius(16)

                Button("Log out", role: .destructive) {
                    authStore.signOut()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why create an account?")
                        .font(.headline)
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Advanced AI summaries and guidance for your sessions.", systemImage: "wand.and.stars")
                        Label("Sync your sessions and bankroll safely across devices.", systemImage: "icloud")
                        Label("See and publish Community sessions with other players.", systemImage: "person.3.sequence.fill")
                        Label("Back up your data so you never lose your history.", systemImage: "clock.arrow.circlepath")
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.black.opacity(0.35))
                .cornerRadius(18)

                Button {
                    authStore.signInWithApple()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                        Text("Sign in with Apple")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
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
                        Text("Sign in with Google")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(authStore.isLoading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Email account")
                        .font(.headline)
                        .foregroundColor(.white)

                    Picker("Email auth mode", selection: $emailAuthMode) {
                        ForEach(EmailAuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $emailInput)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                        .foregroundColor(.white)

                    SecureField("Password", text: $emailPassword)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                        .foregroundColor(.white)

                    if emailAuthMode == .signUp {
                        SecureField("Confirm password", text: $emailPasswordConfirm)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }

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
                        switch emailAuthMode {
                        case .signIn:
                            Task { await authStore.signInWithEmailPassword(email: trimmedEmail, password: emailPassword) }
                        case .signUp:
                            Task { await authStore.signUpWithEmailPassword(email: trimmedEmail, password: emailPassword) }
                        }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(emailAuthMode.buttonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        authStore.isLoading ||
                        emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        emailPassword.isEmpty ||
                        (emailAuthMode == .signUp && emailPasswordConfirm.isEmpty) ||
                        (emailAuthMode == .signUp && emailPasswordConfirm != emailPassword)
                    )
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Continue without an account")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Text("You can continue using TierTap without signing in. For advanced AI features and Community sessions, you’ll need to create and log in to your account.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
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

            await MainActor.run {
                feedSessions = items
                hasMoreFeedPages = items.count == communityPageSize
                availableGames = Array(gamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableLocations = Array(locationsSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                selectedGames = selectedGames.intersection(gamesSet)
                selectedLocations = selectedLocations.intersection(locationsSet)
                isLoadingFeed = false
            }
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

            await MainActor.run {
                feedSessions = allItems
                hasMoreFeedPages = moreItems.count == communityPageSize
                availableGames = Array(gamesSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                availableLocations = Array(locationsSet)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                selectedGames = selectedGames.intersection(gamesSet)
                selectedLocations = selectedLocations.intersection(locationsSet)
                isLoadingFeed = false
            }
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

}

struct CommunityFeedRow: View {
    let item: TableGamePostRow
    let onShowLocation: ((TableGamePostRow) -> Void)?

    private var metrics: TableGamePostMetrics? {
        item.metrics
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: item.created_at)
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

        VStack(alignment: .leading, spacing: 10) {
            // Top row: casino (upper left) with location link, game (upper right)
            HStack {
                HStack(spacing: 6) {
                    Text(casinoName)
                        .font(.headline)
                        .foregroundColor(.white)
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
                Spacer()
                Text(gameName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
            }

            if let comment = item.session_details?.comment, !comment.isEmpty {
                Text(comment)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .italic()
                    .lineLimit(1)
            }

            // Bottom area: pts metrics + Rating Diff on same line, date slightly below
            VStack(alignment: .leading, spacing: 6) {
                // First line: pts/hr (left) and Rating Diff (right)
                HStack(alignment: .center) {
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

                    Spacer()

                    if let diff = betDifferentialPercent {
                        Text("Rating Diff " + String(format: "%+.0f%%", diff))
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(betDifferentialColor)
                            )
                            .accessibilityLabel("Rating diff \(Int(diff)) percent")
                    } else if metrics?.avg_bet_actual != nil || metrics?.avg_bet_rated != nil {
                        Text("Rating Diff N/A")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }

                // Second line: tier delta (left) and date (right)
                HStack(alignment: .center) {
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
                        Text("PTS")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Text(dateString)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CommunityFeedFiltersView: View {
    @Binding var filterStartDate: Date
    @Binding var filterEndDate: Date
    @Binding var selectedGames: Set<String>
    @Binding var selectedLocations: Set<String>

    let availableGames: [String]
    let availableLocations: [String]
    let isLoading: Bool
    let onApply: () -> Void
    let onClear: () -> Void

    @State private var isDateExpanded: Bool = false
    @State private var isGameExpanded: Bool = false
    @State private var isLocationExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button("Clear") {
                    onClear()
                }
                .font(.caption)
                .foregroundColor(.green)
            }

            // Date & time range
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation {
                        isDateExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label("Date & time range", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Image(systemName: isDateExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)

                if isDateExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            DatePicker(
                                "",
                                selection: $filterStartDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            DatePicker(
                                "",
                                selection: $filterEndDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.white)
                        }
                    }
                }
            }

            // Game bubbles (multi-select)
            if !availableGames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation {
                            isGameExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Label("Games", systemImage: "suit.club.fill")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            if !selectedGames.isEmpty {
                                Text("\(selectedGames.count) selected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            Image(systemName: isGameExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)

                    if isGameExpanded {
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
            }

            // Location bubbles (multi-select)
            if !availableLocations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation {
                            isLocationExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Label("Locations", systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            if !selectedLocations.isEmpty {
                                Text("\(selectedLocations.count) selected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            Image(systemName: isLocationExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)

                    if isLocationExpanded {
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
            }

            Button {
                onApply()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Apply Filters")
                    }
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .cornerRadius(10)
            }
            .disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Community feed map

struct CommunityMapLocation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct CommunityFeedMapSheet: View {
    let sessions: [TableGamePostRow]

    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var locations: [CommunityMapLocation] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    )
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()

                if locations.isEmpty && isLoading {
                    ProgressView("Loading locations…")
                        .tint(.white)
                } else if locations.isEmpty {
                    Text("No mapped casino locations for this feed yet.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    Map(coordinateRegion: $region, annotationItems: locations) { loc in
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
            .navigationTitle("Session Map")
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
            .task {
                await loadLocations()
            }
        }
    }

    private func loadLocations() async {
        guard !isLoading else { return }
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

        await MainActor.run {
            isLoading = true
        }

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

            let mapped: [CommunityMapLocation] = decoded.compactMap { row in
                guard
                    let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                    uniqueNames.contains(name),
                    let lat = row.latitude,
                    let lon = row.longitude
                else {
                    return nil
                }

                return CommunityMapLocation(
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            }

            await MainActor.run {
                locations = mapped
                isLoading = false
                updateRegion()
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func updateRegion() {
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

    private var allSelected: Bool {
        !sessions.isEmpty && selectedSessionIDs.count == sessions.count
    }

    private var sortedSessions: [Session] {
        sessions.sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No completed sessions available to publish.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Button {
                                    selectedSessionIDs = Set(sessions.map { $0.id })
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Select All Sessions")
                                            .foregroundColor(.white)
                                    }
                                }

                                Spacer()

                                Button {
                                    selectedSessionIDs.removeAll()
                                } label: {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.red)
                                        Text("Clear All")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.systemGray6).opacity(0.2))
                        }

                        Section(
                            header: Text("Add a short comment (optional)").foregroundColor(.gray),
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

                        Section(header: Text("Choose sessions to publish").foregroundColor(.gray)) {
                            ForEach(sortedSessions) { session in
                                CommunitySessionSelectableRow(
                                    session: session,
                                    isSelected: selectedSessionIDs.contains(session.id)
                                ) {
                                    toggleSelection(for: session)
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Publish Sessions")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publishSelectedSessions() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Publish")
                        }
                    }
                    .foregroundColor(selectedSessionIDs.isEmpty || isPublishing ? .gray : .green)
                    .disabled(selectedSessionIDs.isEmpty || isPublishing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(Color.black.opacity(0.6))
                }
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
                comment: commentToPublish
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
                        Text("•")
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


