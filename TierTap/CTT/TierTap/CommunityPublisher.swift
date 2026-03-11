import Foundation
import Supabase

enum CommunityPublisherError: LocalizedError {
    case supabaseNotConfigured
    case notSignedIn
    case noClient
    case noSessions

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
        }
    }
}

struct CommunityPublisher {
    /// Publish the given sessions to the `TableGamePosts` table.
    /// Returns the number of rows successfully sent.
    /// `currencyCode` and `currencySymbol` are saved into the metrics JSON so the feed can render amounts correctly.
    /// Optional `comment` is stored in each post's session_details JSON and shown in the feed (one line).
    static func publishSessions(
        _ sessions: [Session],
        authStore: AuthStore,
        currencyCode: String,
        currencySymbol: String,
        comment: String? = nil
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

        let payloads: [TableGamePostPayload] = completed.map { s in
            let start = formatter.string(from: s.startTime)
            let end = s.endTime.map { formatter.string(from: $0) }

            let details = TableGamePostSessionDetails(
                session_id: s.id.uuidString,
                casino: s.casino,
                game: s.game,
                start_time: start,
                end_time: end,
                comment: comment.flatMap { let t = $0.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
            )

            let metrics = TableGamePostMetricsPayload(
                duration_seconds: Int(s.duration),
                starting_tier_points: s.startingTierPoints,
                ending_tier_points: s.endingTierPoints,
                tiers_per_hour: s.tiersPerHour,
                avg_bet_actual: s.avgBetActual,
                avg_bet_rated: s.avgBetRated,
                currency_code: currencyCode,
                currency_symbol: currencySymbol
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
}

/// JSON body stored in the `metrics` column when publishing sessions.
/// This intentionally omits `total_buy_in` and `cash_out` so that win/loss amounts
/// are not saved in the metrics JSON for shared sessions.
struct TableGamePostMetricsPayload: Encodable {
    let duration_seconds: Int?
    let starting_tier_points: Int
    let ending_tier_points: Int?
    let tiers_per_hour: Double?
    let avg_bet_actual: Int?
    let avg_bet_rated: Int?
    let currency_code: String?
    let currency_symbol: String?
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


