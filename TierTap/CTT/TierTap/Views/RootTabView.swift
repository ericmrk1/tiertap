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
    @EnvironmentObject var authStore: AuthStore
    @State private var showAuthSheet = false
    @State private var emailInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(settingsStore.primaryGradient)
                        Text("Community Sessions")
                            .font(.title.bold())
                            .foregroundColor(.white)
                        Text("This feature is coming soon. Soon you'll be able to see anonymized community trends, compare your play to other advantage players, and discover new ways to optimize your sessions.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    }
                    .padding()
                }
            }
            .navigationTitle("Community Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAuthSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: authStore.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                            if authStore.isSignedIn {
                                if let emojis = authStore.userProfileEmojis, !emojis.isEmpty {
                                    Text(emojis)
                                        .font(.body)
                                }
                                Text(authStore.signedInSummary ?? authStore.userEmail ?? "Account")
                                    .lineLimit(1)
                                    .font(.caption)
                            } else {
                                Text("Account")
                                    .font(.subheadline)
                            }
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showAuthSheet) {
                CommunityAuthSheet(
                    emailInput: $emailInput,
                    onDismiss: { showAuthSheet = false }
                )
                .environmentObject(authStore)
                .environmentObject(settingsStore)
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

    @State private var profileDisplayName: String = ""
    @State private var profileEmojis: String = ""
    @State private var isSavingProfile = false
    @State private var profileSaved = false

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
        }
        .onChange(of: authStore.session?.user.id) { _ in
            profileDisplayName = authStore.userDisplayName ?? ""
            profileEmojis = authStore.userProfileEmojis ?? ""
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile")
                .font(.title2.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
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

                Text("Emojis")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))
                EmojiPickerView(selection: $profileEmojis)
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

            Button {
                saveProfile()
            } label: {
                HStack {
                    if isSavingProfile {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save profile")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(settingsStore.primaryGradient)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isSavingProfile)
        }
    }

    private func saveProfile() {
        profileSaved = false
        isSavingProfile = true
        Task {
            await authStore.updateProfile(
                displayName: profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                emojis: profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profileEmojis.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if !SupabaseConfig.isConfigured {
                Text("Add SUPABASE_URL and SUPABASE_ANON_KEY to SupabaseKeys.plist to enable sign-in.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if authStore.isSignedIn {
                // Current login info
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(settingsStore.primaryGradient)
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
                            .multilineTextAlignment(.center)
                    }
                    if let emojis = authStore.userProfileEmojis, !emojis.isEmpty {
                        Text(emojis)
                            .font(.title2)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // Profile: display name & emojis (large section)
                profileSection

                Button("Log out", role: .destructive) {
                    authStore.signOut()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Text("Sign in to sync with the community")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

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

                Text("or use email")
                    .font(.caption)
                    .foregroundColor(.gray)

                TextField("Email", text: $emailInput)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                if authStore.otpSent {
                    Text("Check your inbox for the sign-in link.")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                if let msg = authStore.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authStore.signInWithOTP(email: emailInput) }
                } label: {
                    if authStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send magic link")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(authStore.isLoading || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

