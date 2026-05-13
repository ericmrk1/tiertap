import SwiftUI
import UIKit

struct HistoryPhotoFeedView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @State private var selectedSession: Session?
    #if os(iOS)
    @State private var shareSessionRef: PostCloseoutSessionRef?
    #endif

    private var feedEntries: [SessionPhotoCatalog.FeedEntry] {
        var sessions = store.sessions
        if let live = store.liveSession {
            sessions.append(live)
        }
        return SessionPhotoCatalog.feedEntries(from: sessions)
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            if feedEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 28) {
                        ForEach(feedEntries) { entry in
                            HistoryPhotoFeedPost(
                                entry: entry,
                                session: session(for: entry),
                                onImageTap: {
                                    if let session = session(for: entry) {
                                        selectedSession = session
                                    }
                                },
                                onShareTap: {
                                    shareSessionRef = PostCloseoutSessionRef(id: entry.sessionID)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .localizedNavigationTitle("Photo Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .adaptiveSheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(rewardWalletStore)
                .environmentObject(subscriptionStore)
                .environmentObject(authStore)
        }
        #if os(iOS)
        .sheet(item: $shareSessionRef) { ref in
            PostCloseoutShareFlowView(sessionId: ref.id)
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(subscriptionStore)
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundColor(.gray)
            L10nText("No session photos yet.")
                .font(.title3)
                .foregroundColor(.gray)
            L10nText("Photos from live sessions, comps, and session galleries will appear here.")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func session(for entry: SessionPhotoCatalog.FeedEntry) -> Session? {
        if let live = store.liveSession, live.id == entry.sessionID {
            return live
        }
        return store.sessions.first(where: { $0.id == entry.sessionID })
    }
}

private struct HistoryPhotoFeedPost: View {
    let entry: SessionPhotoCatalog.FeedEntry
    let session: Session?
    let onImageTap: () -> Void
    let onShareTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sessionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(entry.sessionDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer(minLength: 0)

                if session != nil {
                    Button(action: onShareTap) {
                        Label {
                            L10nText("Share")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share session")
                }
            }

            Button(action: onImageTap) {
                Group {
                    if let session,
                       let image = SessionPhotoCatalog.image(for: entry.ref, session: session) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray6).opacity(0.25)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, maxHeight: 420)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(session == nil)
        }
    }
}
