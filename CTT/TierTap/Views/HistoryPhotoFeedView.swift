import SwiftUI
import UIKit

private enum HistoryPhotoFeedFilter: String, CaseIterable, Identifiable {
    case allPhotos
    case primaryOnly

    var id: String { rawValue }
}

struct HistoryPhotoFeedView: View {
    private static let pageSize = 12

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var rewardWalletStore: RewardWalletStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var authStore: AuthStore
    @State private var selectedSession: Session?
    @State private var photoFeedFilter: HistoryPhotoFeedFilter = .allPhotos
    @State private var selectedContextFilterKeys: Set<String> = []
    @State private var visibleEntryLimit = HistoryPhotoFeedView.pageSize
    #if os(iOS)
    @State private var shareSessionRef: PostCloseoutSessionRef?
    #endif

    private var feedSessions: [Session] {
        var sessions = store.sessions
        if let live = store.liveSession {
            sessions.append(live)
        }
        return sessions
    }

    private var feedEntries: [SessionPhotoCatalog.FeedEntry] {
        SessionPhotoCatalog.feedEntries(from: feedSessions)
    }

    private var contextFilterOptions: [SessionPhotoCatalog.ContextFilterOption] {
        SessionPhotoCatalog.contextFilterOptions(from: feedSessions)
    }

    private var displayedFeedEntries: [SessionPhotoCatalog.FeedEntry] {
        let base: [SessionPhotoCatalog.FeedEntry]
        switch photoFeedFilter {
        case .allPhotos:
            base = feedEntries
        case .primaryOnly:
            base = feedEntries.filter { entry in
                guard let session = session(for: entry),
                      let primary = SessionPhotoCatalog.resolvedPrimaryRef(for: session) else {
                    return false
                }
                return entry.ref == primary
            }
        }
        guard !selectedContextFilterKeys.isEmpty else { return base }
        return base.filter { entry in
            guard let session = session(for: entry) else { return false }
            return session.matchesContextFilters(selectedContextFilterKeys, for: entry.ref)
        }
    }

    private var paginatedFeedEntries: [SessionPhotoCatalog.FeedEntry] {
        Array(displayedFeedEntries.prefix(visibleEntryLimit))
    }

    private var hasMoreFeedEntries: Bool {
        visibleEntryLimit < displayedFeedEntries.count
    }

    var body: some View {
        ZStack {
            settingsStore.primaryGradient.ignoresSafeArea()
            if feedEntries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    photoFeedFilterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if displayedFeedEntries.isEmpty {
                        filteredEmptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 28) {
                                ForEach(paginatedFeedEntries) { entry in
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
                                    .onAppear {
                                        if entry.id == paginatedFeedEntries.last?.id {
                                            loadMoreFeedEntriesIfNeeded()
                                        }
                                    }
                                }

                                if hasMoreFeedEntries {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .onAppear {
                                            loadMoreFeedEntriesIfNeeded()
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                        }
                    }
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
        .onChange(of: photoFeedFilter) { _ in
            resetFeedPagination()
        }
        .onChange(of: selectedContextFilterKeys) { _ in
            resetFeedPagination()
        }
        .onChange(of: feedEntriesSignature) { _ in
            resetFeedPagination()
            pruneStaleContextFilters()
        }
    }

    private func pruneStaleContextFilters() {
        let valid = Set(contextFilterOptions.map(\.id))
        selectedContextFilterKeys = selectedContextFilterKeys.intersection(valid)
    }

    private func resetFeedPagination() {
        visibleEntryLimit = Self.pageSize
    }

    private func loadMoreFeedEntriesIfNeeded() {
        guard hasMoreFeedEntries else { return }
        visibleEntryLimit = min(visibleEntryLimit + Self.pageSize, displayedFeedEntries.count)
    }

    private var feedEntriesSignature: String {
        feedEntries.map(\.id).joined(separator: "|")
    }

    private var photoFeedFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $photoFeedFilter) {
                Text("All photos").tag(HistoryPhotoFeedFilter.allPhotos)
                Text("Primary").tag(HistoryPhotoFeedFilter.primaryOnly)
            }
            .pickerStyle(.segmented)

            if !contextFilterOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Context")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                        if !selectedContextFilterKeys.isEmpty {
                            Button("Clear") {
                                selectedContextFilterKeys = []
                            }
                            .font(.caption2)
                            .foregroundColor(.green)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(contextFilterOptions) { option in
                                let isSelected = selectedContextFilterKeys.contains(option.id)
                                Button {
                                    if isSelected {
                                        selectedContextFilterKeys.remove(option.id)
                                    } else {
                                        selectedContextFilterKeys.insert(option.id)
                                    }
                                } label: {
                                    Text(option.label)
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

    private var filteredEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedContextFilterKeys.isEmpty ? "star" : "tag")
                .font(.system(size: 44))
                .foregroundColor(.gray)
            if !selectedContextFilterKeys.isEmpty {
                L10nText("No photos match these context tags.")
                    .font(.title3)
                    .foregroundColor(.gray)
                L10nText("Try clearing context filters or choosing different tags.")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else {
                L10nText("No primary photos to show.")
                    .font(.title3)
                    .foregroundColor(.gray)
                L10nText("Choose a primary photo in session details or edit session.")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
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

    private var sessionMetadataText: String {
        var parts = [entry.sessionDate.formatted(date: .abbreviated, time: .shortened)]
        if let session {
            parts.append(Session.durationString(session.duration))
        }
        return parts.joined(separator: " · ")
    }

    private var contextTags: [SessionPhotoContextTag] {
        session?.contextTags(for: entry.ref) ?? []
    }

    private var customContextLabels: [String] {
        session?.customContextLabels(for: entry.ref) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sessionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(sessionMetadataText)
                        .font(.caption.monospacedDigit())
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
                HistoryPhotoFeedImage(entry: entry, session: session)
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

            SessionPhotoContextTagBadgeRow(tags: contextTags, customLabels: customContextLabels)
        }
    }
}

private struct HistoryPhotoFeedImage: View {
    let entry: SessionPhotoCatalog.FeedEntry
    let session: Session?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if session == nil {
                Color(.systemGray6).opacity(0.25)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
            } else {
                Color(.systemGray6).opacity(0.25)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .task(id: entry.id) {
            image = nil
            guard let session else { return }
            let ref = entry.ref
            let loaded = await Task.detached(priority: .utility) {
                SessionPhotoCatalog.image(for: ref, session: session)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
