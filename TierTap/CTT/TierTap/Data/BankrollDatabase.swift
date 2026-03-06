import Foundation
import SQLite3

/// Dedicated SQLite database for bankroll data. Stores resets and session impacts for analytics and graph generation.
/// File location: Application Support/tiertap_bankroll.sqlite
final class BankrollDatabase {
    static let shared = BankrollDatabase()
    private var db: OpaquePointer?
    private let dbFileName = "tiertap_bankroll.sqlite"
    private let queue = DispatchQueue(label: "com.tiertap.bankroll.db", qos: .userInitiated)

    private init() {}

    private var dbURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("TierTap", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir.appendingPathComponent(dbFileName)
    }

    /// Open or create the database. Call at app launch or before first use. Thread-safe.
    func open() {
        queue.sync { performOpen() }
    }

    private func performOpen() {
        guard db == nil else { return }
        let path = dbURL.path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            return
        }
        executeSchema()
        migrateFromUserDefaults()
    }

    private func executeSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS bankroll_resets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date REAL NOT NULL,
            value INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS bankroll_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT UNIQUE NOT NULL,
            date REAL NOT NULL,
            win_loss INTEGER NOT NULL,
            casino TEXT,
            game TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_resets_date ON bankroll_resets(date);
        CREATE INDEX IF NOT EXISTS idx_sessions_date ON bankroll_sessions(date);
        """
        sql.split(separator: ";").forEach { stmt in
            let s = String(stmt).trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return }
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            if sqlite3_prepare_v2(db, s, -1, &st, nil) == SQLITE_OK {
                sqlite3_step(st)
            }
        }
    }

    /// Migrate existing UserDefaults bankroll resets into SQLite (one-time).
    private func migrateFromUserDefaults() {
        let key = "ctt_bankroll_resets"
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BankrollResetEvent].self, from: data),
              !decoded.isEmpty else { return }
        for event in decoded {
            insertReset(date: event.date, value: event.value)
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Resets

    func fetchResets() -> [BankrollResetEvent] {
        queue.sync {
            openIfNeeded()
            let sql = "SELECT date, value FROM bankroll_resets ORDER BY date ASC"
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            var results: [BankrollResetEvent] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let dateVal = sqlite3_column_double(st, 0)
                let value = Int(sqlite3_column_int(st, 1))
                results.append(BankrollResetEvent(date: Date(timeIntervalSince1970: dateVal), value: value))
            }
            return results
        }
    }

    func insertReset(date: Date, value: Int) {
        queue.sync {
            openIfNeeded()
            let sql = "INSERT INTO bankroll_resets (date, value) VALUES (?, ?)"
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_double(st, 1, date.timeIntervalSince1970)
                sqlite3_bind_int(st, 2, Int32(value))
                sqlite3_step(st)
            }
        }
    }

    // MARK: - Session impacts (for analytics)

    /// Sync session win/loss data from SessionStore. Call when sessions change.
    /// Enables SQL-based analytics and graph queries.
    func syncSessions(_ sessions: [Session]) {
        queue.sync {
            openIfNeeded()
            let withWL = sessions.filter { $0.winLoss != nil }
            // Delete and replace for simplicity; could use upsert for production
            execute("DELETE FROM bankroll_sessions")
            for s in withWL {
                insertSession(id: s.id.uuidString, date: s.startTime, winLoss: s.winLoss!, casino: s.casino, game: s.game)
            }
        }
    }

    private func insertSession(id: String, date: Date, winLoss: Int, casino: String, game: String) {
        let sql = "INSERT INTO bankroll_sessions (session_id, date, win_loss, casino, game) VALUES (?, ?, ?, ?, ?)"
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_double(st, 2, date.timeIntervalSince1970)
            sqlite3_bind_int(st, 3, Int32(winLoss))
            sqlite3_bind_text(st, 4, (casino as NSString).utf8String, -1, nil)
            sqlite3_bind_text(st, 5, (game as NSString).utf8String, -1, nil)
            sqlite3_step(st)
        }
    }

    // MARK: - Analytics helpers (for future graph/query features)

    /// Raw database path for external analytics tools or debugging.
    var databasePath: String { dbURL.path }

    /// Fetch bankroll timeline points (date, value) from SQL. Useful for date-range queries and aggregations.
    func fetchTimelinePoints(from startDate: Date? = nil, to endDate: Date? = nil) -> [(date: Date, value: Int)] {
        // Timeline is computed from resets + sessions; SQLite has both.
        // For now return empty; callers can use Swift logic. Future: materialize or use CTE.
        []
    }

    private func execute(_ sql: String) {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
            sqlite3_step(st)
        }
    }

    private func openIfNeeded() {
        if db == nil { performOpen() }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}
