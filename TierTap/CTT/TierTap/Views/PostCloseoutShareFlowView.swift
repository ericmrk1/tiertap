import SwiftUI

#if os(iOS)
/// Identifies which session triggered the post-closeout share sheet (used with `sheet(item:)`).
struct PostCloseoutSessionRef: Identifiable, Hashable {
    let id: UUID
}

/// Bottom-of-flow choices after completing a live session: session art or community publish.
struct PostCloseoutShareFlowView: View {
    let sessionId: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .pickAction

    private enum Step {
        case pickAction
        case communityPublish
        case sessionArt
    }

    /// Completed history sessions plus the in-progress live session when this flow targets it (not yet in `sessions`).
    private var sessionsForCommunityPublish: [Session] {
        let completed = store.sessions.filter { $0.isComplete }
        guard let live = store.liveSession, live.id == sessionId,
              !completed.contains(where: { $0.id == live.id }) else { return completed }
        return [live] + completed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pickAction:
                    pickActionPanel
                        .toolbar(.hidden, for: .navigationBar)
                case .communityPublish:
                    CommunitySessionPublishSelectionView(
                        sessions: sessionsForCommunityPublish,
                        initialSelectedSessionIDs: Set([sessionId]),
                        onBackFromSelection: { step = .pickAction },
                        onFinished: { _ in dismiss() }
                    )
                    .environmentObject(settingsStore)
                    .environmentObject(authStore)
                case .sessionArt:
                    SessionArtGeneratorView(sessionId: sessionId) {
                        step = .pickAction
                    }
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationDetents(step == .pickAction ? [.fraction(0.25)] : [.large])
        .presentationDragIndicator(.visible)
    }

    private var pickActionPanel: some View {
        ZStack(alignment: .topTrailing) {
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
                            step = .sessionArt
                        } label: {
                            Label("Generate Session Art", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.red)
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

                        Button("Not now", role: .cancel) {
                            dismiss()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }
            Button("Close") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
                .padding(.top, 6)
                .padding(.trailing, 12)
        }
    }
}
#endif
