import Foundation
import Supabase

enum CommunityPublisherError: LocalizedError {
    case supabaseNotConfigured
    case notSignedIn
    case noClient
    case noSessions
    case screenNameNotRegistered
    case profilePhotoShareFailed(String)

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            return "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to SupabaseKeys.plist."
        case .notSignedIn:
            return "You need to be signed in to publish sessions."
        case .noClient:
            return "Unable to create Supabase client."
        case .noSessions:
            return "There are no sessions to publish."
        case .screenNameNotRegistered:
            return "Save a unique screen name in Community → Account before publishing. Open Account from the Community tab, choose a name that is not already taken, then tap Save profile."
        case .profilePhotoShareFailed(let detail):
            return detail
        }
    }
}

struct CommunityPublisher {
    /// Publish the given sessions to the `TableGamePosts` table.
    /// Returns the number of rows successfully sent.
    /// `currencyCode` and `currencySymbol` are saved into the metrics JSON so the feed can render amounts correctly.
    /// Optional `comment` is stored in each post's session_details JSON and shown in the feed (one line).
    /// When `publishTierPerHour` is true, `tiers_per_hour` is included in metrics; otherwise it is omitted.
    /// When `publishWinLoss` is true, buy-in, cash-out, net win/loss, total comps, and EV (expected value = net + comps) are included in metrics.
    /// When `publishCompDetails` is true, `comp_count` and `comp_value_total` (sum of logged comp amounts) are included for sessions that have comps.
    /// When `publishFreePlayTotal` is true, `total_free_play` is included for sessions with logged free play (promotional value, not cash P&L).
    /// When `attachScreenName` is false, `session_details.screen_name` is omitted so the post appears as Anonymous in the feed (still tied to your account on the server).
    /// When `attachProfilePhoto` is true, the chosen photo is uploaded to Storage and `session_details.avatar_path` is set so the feed can show it. Older posts omit the field and keep a placeholder.
    static func publishSessions(
        _ sessions: [Session],
        authStore: AuthStore,
        currencyCode: String,
        currencySymbol: String,
        comment: String? = nil,
        publishTierPerHour: Bool = true,
        publishWinLoss: Bool = false,
        publishCompDetails: Bool = false,
        publishFreePlayTotal: Bool = true,
        attachScreenName: Bool = true,
        attachProfilePhoto: Bool = false,
        profilePhotoSource: CommunityProfilePhotoShareSource = .tierTap
    ) async throws -> Int {
        guard SupabaseConfig.isConfigured else {
            throw CommunityPublisherError.supabaseNotConfigured
        }

        // AuthStore is @MainActor; read its session on the main actor
        guard let session = await MainActor.run(body: { authStore.session }) else {
            throw CommunityPublisherError.notSignedIn
        }
        guard let client = supabase else {
            throw CommunityPublisherError.noClient
        }
        let completed = sessions.filter { $0.isComplete }
        guard !completed.isEmpty else {
            throw CommunityPublisherError.noSessions
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let userId = session.user.id
        let screenNameForPost: String?
        if attachScreenName {
            let registered = try await UserScreenNamesAPI.fetchRegisteredScreenName(userId: userId)
            guard let name = registered, !name.isEmpty else {
                throw CommunityPublisherError.screenNameNotRegistered
            }
            screenNameForPost = name
        } else {
            screenNameForPost = nil
        }

        let avatarPathForPost: String?
        if attachProfilePhoto {
            do {
                avatarPathForPost = try await authStore.uploadAvatarForCommunityShare(source: profilePhotoSource)
            } catch let error as LocalizedError {
                throw CommunityPublisherError.profilePhotoShareFailed(
                    error.errorDescription ?? "Could not share your profile photo."
                )
            } catch {
                throw CommunityPublisherError.profilePhotoShareFailed(error.localizedDescription)
            }
        } else {
            avatarPathForPost = nil
        }

        let payloads: [TableGamePostPayload] = completed.map { s in
            let start = formatter.string(from: s.startTime)
            let end = s.endTime.map { formatter.string(from: $0) }

            let details = TableGamePostSessionDetails(
                session_id: s.id.uuidString,
                casino: s.casino,
                game: s.game,
                start_time: start,
                end_time: end,
                comment: comment.flatMap { let t = $0.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t },
                screen_name: screenNameForPost,
                captured_on_apple_watch: s.capturedOnAppleWatch,
                avatar_path: avatarPathForPost
            )

            let includeCompSummary = publishCompDetails && !s.compEvents.isEmpty
            let includeFreePlayTotal = publishFreePlayTotal && s.totalFreePlay > 0
            let metrics = TableGamePostMetricsPayload(
                duration_seconds: Int(s.duration),
                starting_tier_points: s.startingTierPoints,
                ending_tier_points: s.endingTierPoints,
                tiers_per_hour: publishTierPerHour ? s.tiersPerHour : nil,
                avg_bet_actual: s.avgBetActual,
                avg_bet_rated: s.avgBetRated,
                currency_code: currencyCode,
                currency_symbol: currencySymbol,
                total_buy_in: publishWinLoss ? s.totalBuyIn : nil,
                cash_out: publishWinLoss ? s.cashOut : nil,
                net_win_loss: publishWinLoss ? s.winLoss : nil,
                total_comp: publishWinLoss ? s.totalComp : nil,
                expected_value: publishWinLoss ? s.expectedValue : nil,
                comp_count: includeCompSummary ? s.compEvents.count : nil,
                comp_value_total: includeCompSummary ? s.totalComp : nil,
                total_free_play: includeFreePlayTotal ? s.totalFreePlay : nil
            )

            return TableGamePostPayload(
                session_details: details,
                location: s.casino,
                game: s.game,
                metrics: metrics,
                user_id: session.user.id
            )
        }

        _ = try await client.database
            .from(SupabaseTables.tableGamePosts)
            .insert(payloads)
            .execute()

        return payloads.count
    }
}

/// Encodable payload matching the `TableGamePosts` table in Supabase.
struct TableGamePostPayload: Encodable {
    let session_details: TableGamePostSessionDetails
    let location: String
    let game: String
    let metrics: TableGamePostMetricsPayload
    let user_id: UUID
}

/// JSON body stored in the `session_details` column.
struct TableGamePostSessionDetails: Codable {
    let session_id: String
    let casino: String
    let game: String
    let start_time: String
    let end_time: String?
    /// Optional short comment from the poster; shown as one line in the feed.
    let comment: String?
    /// TierTap account screen name at publish time; shown in Community and used for filters.
    let screen_name: String?
    /// Present when the session was tracked from Apple Watch.
    let captured_on_apple_watch: Bool?
    /// Optional Storage path in the `avatars` bucket when the poster opted to share a profile photo.
    /// Omitted on legacy posts — feed shows a placeholder. Example: `{userId}/avatar.jpg`.
    let avatar_path: String?
}

/// JSON body stored in the `metrics` column when reading from the feed.
struct TableGamePostMetrics: Codable {
    let duration_seconds: Int?
    let starting_tier_points: Int
    let ending_tier_points: Int?
    let tiers_per_hour: Double?
    let avg_bet_actual: Int?
    let avg_bet_rated: Int?
    let currency_code: String?
    let currency_symbol: String?
    /// Present when the poster opted in to sharing win/loss for this post.
    let total_buy_in: Int?
    let cash_out: Int?
    let net_win_loss: Int?
    /// Total comps (currency units) when shared with win/loss.
    let total_comp: Int?
    /// Win/loss plus comps (EV) when shared with win/loss.
    let expected_value: Int?
    /// Number of comp line items when the poster shared comp details (independent of win/loss).
    let comp_count: Int?
    /// Sum of logged comp amounts (estimated cash value) when the poster shared comp details.
    let comp_value_total: Int?
    /// Total logged free play (promotional value) when the poster opted in; not included in net win/loss.
    let total_free_play: Int?
}

/// JSON body stored in the `metrics` column when publishing sessions.
/// Buy-in, cash-out, and net win/loss are only included when the user enables “Publish wins / losses”.
struct TableGamePostMetricsPayload: Encodable {
    let duration_seconds: Int?
    let starting_tier_points: Int
    let ending_tier_points: Int?
    let tiers_per_hour: Double?
    let avg_bet_actual: Int?
    let avg_bet_rated: Int?
    let currency_code: String?
    let currency_symbol: String?
    let total_buy_in: Int?
    let cash_out: Int?
    let net_win_loss: Int?
    let total_comp: Int?
    let expected_value: Int?
    let comp_count: Int?
    let comp_value_total: Int?
    let total_free_play: Int?
}

/// Decodable row type for reading from the `TableGamePosts` table.
struct TableGamePostRow: Decodable, Identifiable {
    let id: Int64
    let created_at: Date
    let session_details: TableGamePostSessionDetails?
    let location: String?
    let game: String?
    let metrics: TableGamePostMetrics?
    let user_id: UUID?
}

extension TableGamePostRow {
    /// Screen name stored on the post (`session_details.screen_name`). Nil for legacy rows or empty values.
    var feedScreenName: String? {
        guard let raw = session_details?.screen_name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Avatar Storage path when the poster opted in (`session_details.avatar_path`). Nil for legacy / anonymous-photo posts.
    var feedAvatarPath: String? {
        guard let raw = session_details?.avatar_path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}

/// Navigation identity for a Community author profile (screen name or anonymous + user).
struct CommunityAuthorRef: Hashable, Identifiable {
    let screenName: String?
    let userId: UUID?
    let avatarPath: String?
    let displayName: String

    var id: String {
        if let screenName {
            return "name:\(screenName.lowercased())"
        }
        if let userId {
            return "anon:\(userId.uuidString.lowercased())"
        }
        return "anon:unknown"
    }

    init(from post: TableGamePostRow, anonymousLabel: String) {
        screenName = post.feedScreenName
        userId = post.user_id
        avatarPath = post.feedAvatarPath
        displayName = post.feedScreenName ?? anonymousLabel
    }
}

enum CommunityAuthorPostsAPI {
    static let pageSize = 50

    /// One page of posts for a Community author.
    /// - Named authors match `session_details.screen_name`.
    /// - Anonymous authors match `user_id` and only include posts without a screen name.
    /// `rawFetchedCount` is the server page size before anonymous filtering (use for `hasMore`).
    static func fetchPosts(
        for author: CommunityAuthorRef,
        offset: Int = 0,
        limit: Int = pageSize
    ) async throws -> (rows: [TableGamePostRow], rawFetchedCount: Int) {
        guard SupabaseConfig.isConfigured else {
            throw CommunityPostReactionsError.supabaseNotConfigured
        }
        guard let client = supabase else {
            throw CommunityPostReactionsError.noClient
        }

        let from = max(0, offset)
        let to = from + max(1, limit) - 1

        if let screenName = author.screenName {
            let rows: [TableGamePostRow] = try await client.database
                .from(SupabaseTables.tableGamePosts)
                .select()
                .eq("session_details->>screen_name", value: screenName)
                .order("created_at", ascending: false)
                .range(from: from, to: to)
                .execute()
                .value
            return (rows, rows.count)
        }

        guard let userId = author.userId else { return ([], 0) }

        let rows: [TableGamePostRow] = try await client.database
            .from(SupabaseTables.tableGamePosts)
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        // Keep anonymous profile posts anonymous-only; pagination uses raw page size.
        return (rows.filter { $0.feedScreenName == nil }, rows.count)
    }
}

// MARK: - Community post reactions

enum CommunityReactionType: String, Codable, CaseIterable, Hashable {
    case like
    case dislike
    case heart

    var systemImage: String {
        switch self {
        case .like: return "hand.thumbsup"
        case .dislike: return "hand.thumbsdown"
        case .heart: return "heart"
        }
    }

    var systemImageFilled: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .dislike: return "hand.thumbsdown.fill"
        case .heart: return "heart.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .like: return "Like"
        case .dislike: return "Dislike"
        case .heart: return "Heart"
        }
    }
}

struct CommunityPostReactionSummary: Equatable {
    var likeCount: Int = 0
    var dislikeCount: Int = 0
    var heartCount: Int = 0
    var viewerLiked: Bool = false
    var viewerDisliked: Bool = false
    var viewerHearted: Bool = false

    static let empty = CommunityPostReactionSummary()

    func count(for type: CommunityReactionType) -> Int {
        switch type {
        case .like: return likeCount
        case .dislike: return dislikeCount
        case .heart: return heartCount
        }
    }

    func viewerHas(_ type: CommunityReactionType) -> Bool {
        switch type {
        case .like: return viewerLiked
        case .dislike: return viewerDisliked
        case .heart: return viewerHearted
        }
    }

    mutating func applyOptimisticToggle(of type: CommunityReactionType) {
        switch type {
        case .like:
            if viewerLiked {
                viewerLiked = false
                likeCount = max(0, likeCount - 1)
            } else {
                viewerLiked = true
                likeCount += 1
                if viewerDisliked {
                    viewerDisliked = false
                    dislikeCount = max(0, dislikeCount - 1)
                }
            }
        case .dislike:
            if viewerDisliked {
                viewerDisliked = false
                dislikeCount = max(0, dislikeCount - 1)
            } else {
                viewerDisliked = true
                dislikeCount += 1
                if viewerLiked {
                    viewerLiked = false
                    likeCount = max(0, likeCount - 1)
                }
            }
        case .heart:
            if viewerHearted {
                viewerHearted = false
                heartCount = max(0, heartCount - 1)
            } else {
                viewerHearted = true
                heartCount += 1
            }
        }
    }
}

enum CommunityPostReactionsError: LocalizedError {
    case supabaseNotConfigured
    case notSignedIn
    case noClient
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            return "Supabase is not configured."
        case .notSignedIn:
            return "You need to be signed in to react to posts."
        case .noClient:
            return "Unable to create Supabase client."
        case .requestFailed(let message):
            return message
        }
    }
}

enum CommunityPostReactionsAPI {
    private struct CountRow: Decodable {
        let post_id: Int64
        let like_count: Int
        let dislike_count: Int
        let heart_count: Int
    }

    private struct ViewerReactionRow: Decodable {
        let post_id: Int64
        let reaction_type: String
    }

    private struct ReactionInsert: Encodable {
        let post_id: Int64
        let user_id: UUID
        let reaction_type: String
    }

    /// Public avatar URL for a Community author (`avatars/{userId}/avatar.jpg`). May 404 if no photo was uploaded.
    static func avatarPublicURL(for userId: UUID) -> URL? {
        avatarPublicURL(path: AuthStore.communityAvatarStoragePath(for: userId))
    }

    /// Public URL for a Storage path stamped onto a post (`session_details.avatar_path`).
    static func avatarPublicURL(path: String) -> URL? {
        guard let client = supabase else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? client.storage.from("avatars").getPublicURL(path: trimmed)
    }

    /// Loads running totals from ``CommunityPostReactionCounts`` plus the viewer’s own ledger flags.
    static func fetchSummaries(
        postIds: [Int64],
        viewerUserId: UUID?
    ) async throws -> [Int64: CommunityPostReactionSummary] {
        guard !postIds.isEmpty else { return [:] }
        guard SupabaseConfig.isConfigured else {
            throw CommunityPostReactionsError.supabaseNotConfigured
        }
        guard let client = supabase else {
            throw CommunityPostReactionsError.noClient
        }

        let idValues = postIds.map { Int($0) }

        let countRows: [CountRow] = try await client.database
            .from(SupabaseTables.communityPostReactionCounts)
            .select("post_id,like_count,dislike_count,heart_count")
            .in("post_id", values: idValues)
            .execute()
            .value

        var summaries: [Int64: CommunityPostReactionSummary] = [:]
        for id in postIds {
            summaries[id] = .empty
        }
        for row in countRows {
            var summary = summaries[row.post_id] ?? .empty
            summary.likeCount = row.like_count
            summary.dislikeCount = row.dislike_count
            summary.heartCount = row.heart_count
            summaries[row.post_id] = summary
        }

        guard let viewerUserId else { return summaries }

        // RLS limits this to the caller’s own rows.
        let viewerRows: [ViewerReactionRow] = try await client.database
            .from(SupabaseTables.communityPostReactions)
            .select("post_id,reaction_type")
            .eq("user_id", value: viewerUserId)
            .in("post_id", values: idValues)
            .execute()
            .value

        for row in viewerRows {
            guard let type = CommunityReactionType(rawValue: row.reaction_type) else { continue }
            var summary = summaries[row.post_id] ?? .empty
            switch type {
            case .like: summary.viewerLiked = true
            case .dislike: summary.viewerDisliked = true
            case .heart: summary.viewerHearted = true
            }
            summaries[row.post_id] = summary
        }
        return summaries
    }

    /// Toggles a reaction for the signed-in user. Like and dislike are mutually exclusive; heart is independent.
    /// Running totals on ``CommunityPostReactionCounts`` are maintained by a database trigger.
    @discardableResult
    static func toggle(
        postId: Int64,
        type: CommunityReactionType,
        currentlyActive: Bool,
        currentlyHasOpposingLikeDislike: Bool,
        userId: UUID
    ) async throws -> CommunityReactionType? {
        guard SupabaseConfig.isConfigured else {
            throw CommunityPostReactionsError.supabaseNotConfigured
        }
        guard let client = supabase else {
            throw CommunityPostReactionsError.noClient
        }

        if currentlyActive {
            try await client.database
                .from(SupabaseTables.communityPostReactions)
                .delete()
                .eq("post_id", value: Int(postId))
                .eq("user_id", value: userId)
                .eq("reaction_type", value: type.rawValue)
                .execute()
            return nil
        }

        // Like ↔ dislike mutual exclusion
        if currentlyHasOpposingLikeDislike, type == .like || type == .dislike {
            let opposing: CommunityReactionType = (type == .like) ? .dislike : .like
            try await client.database
                .from(SupabaseTables.communityPostReactions)
                .delete()
                .eq("post_id", value: Int(postId))
                .eq("user_id", value: userId)
                .eq("reaction_type", value: opposing.rawValue)
                .execute()
        }

        try await client.database
            .from(SupabaseTables.communityPostReactions)
            .insert(
                ReactionInsert(
                    post_id: postId,
                    user_id: userId,
                    reaction_type: type.rawValue
                )
            )
            .execute()
        return type
    }
}

enum CommunityFeedFormatting {
    /// Threads-style relative age (`13h`, `2d`).
    static func relativeTimestamp(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(max(seconds, 1))s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Compact count for reaction chips (`2.8K`).
    static func compactCount(_ value: Int) -> String {
        let n = max(0, value)
        if n < 1_000 { return "\(n)" }
        if n < 10_000 {
            let tenths = Double(n) / 100.0
            let rounded = (tenths.rounded()) / 10.0
            if rounded.rounded() == rounded {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        if n < 1_000_000 {
            return "\(n / 1_000)K"
        }
        let millions = Double(n) / 1_000_000.0
        if millions < 10 {
            return String(format: "%.1fM", millions)
        }
        return "\(Int(millions))M"
    }
}


