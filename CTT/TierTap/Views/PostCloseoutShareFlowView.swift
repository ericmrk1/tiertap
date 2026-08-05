import SwiftUI

#if os(iOS)
/// Identifies which session triggered the post-closeout share sheet (used with `sheet(item:)`).
struct PostCloseoutSessionRef: Identifiable, Hashable {
    let id: UUID
}

/// Bottom-of-flow choices after completing a live session: quick share, session art, or community publish.
struct PostCloseoutShareFlowView: View {
    let sessionId: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .pickAction
    @State private var shareTextItem: IdentifiableShareText?

    private enum Step {
        case pickAction
        case communityPublish
        case quickShare
        case sessionArt
        case sessionArtText
    }

    private struct IdentifiableShareText: Identifiable {
        let id = UUID()
        let text: String
    }

    /// Completed history sessions plus the in-progress live session when this flow targets it (not yet in `sessions`).
    private var sessionsForCommunityPublish: [Session] {
        let completed = store.sessions.filter { $0.isComplete }
        guard let live = store.liveSession, live.id == sessionId,
              !completed.contains(where: { $0.id == live.id }) else { return completed }
        return [live] + completed
    }

    private var resolvedSession: Session? {
        if let saved = store.sessions.first(where: { $0.id == sessionId }) { return saved }
        if store.liveSession?.id == sessionId { return store.liveSession }
        return nil
    }

    var body: some View {
        Group {
            switch step {
            case .pickAction:
                // Avoid wrapping the compact “pick action” UI in `NavigationStack`; that often
                // causes the system to ignore `.fraction` detents and present near full height.
                pickActionPanel
            case .quickShare:
                SessionArtQuickShareSheet(
                    sessionId: sessionId,
                    onCustomize: { step = .sessionArt },
                    onShareText: { step = .sessionArtText }
                )
                .environmentObject(store)
                .environmentObject(settingsStore)
            case .communityPublish:
                CommunitySessionPublishSelectionView(
                    sessions: sessionsForCommunityPublish,
                    initialSelectedSessionIDs: Set([sessionId]),
                    onBackFromSelection: { step = .pickAction },
                    onFinished: { result in
                        if case .success(let count) = result {
                            store.communityPublishToastMessage = count == 1 ?
                                "Published 1 session to the community." :
                                "Published \(count) sessions to the community."
                        }
                        dismiss()
                    }
                )
                .environmentObject(settingsStore)
                .environmentObject(authStore)
                .environmentObject(store)
            case .sessionArt:
                NavigationStack {
                    SessionArtGeneratorView(sessionId: sessionId) {
                        step = .pickAction
                    }
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                }
            case .sessionArtText:
                NavigationStack {
                    SessionArtGeneratorView(sessionId: sessionId, initialOutputKind: "Text") {
                        step = .pickAction
                    }
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                    .environmentObject(subscriptionStore)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents(step == .pickAction ? [.fraction(0.42)] : [.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $shareTextItem) { item in
            ShareSheet(items: [item.text])
        }
    }

    private var pickActionPanel: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    L10nText("Share this session?")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 8) {
                        Button {
                            step = .quickShare
                        } label: {
                            Label("Quick Share", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            step = .sessionArt
                        } label: {
                            Label("Customize Session Art", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.blue.opacity(0.85))
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            shareTextStoryDirectly()
                        } label: {
                            Label("Share text story", systemImage: "text.alignleft")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.white.opacity(0.18))
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            step = .communityPublish
                        } label: {
                            Label("Community Publish", systemImage: "paperplane.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.green.opacity(0.85))
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Text("Not now")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func shareTextStoryDirectly() {
        guard let session = resolvedSession else {
            step = .sessionArtText
            return
        }
        let text = SessionShareFormatter.combinedMessage(
            for: [session],
            currencySymbol: settingsStore.currencySymbol,
            includeWinLoss: false
        )
        shareTextItem = IdentifiableShareText(text: text)
    }
}
#endif
