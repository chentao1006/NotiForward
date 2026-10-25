import Foundation
import SQLite3

enum LocalStoreError: Error, LocalizedError {
    case unavailableContainer
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .unavailableContainer: return "The Application Support directory is unavailable."
        case .sqlite(let message): return message
        }
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    var pointer: OpaquePointer?
    deinit { if let pointer { sqlite3_close(pointer) } }
}

actor LocalStore {
    private let connection: SQLiteConnection
    private var db: OpaquePointer? { connection.pointer }

    init() throws {
        let connection = SQLiteConnection()
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalStoreError.unavailableContainer
        }
        let directory = applicationSupport.appending(path: "NotiForward", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "noti-forward.sqlite")
#if !APP_STORE
        Self.migrateFromUnsandboxedLocation(to: url)
#endif
        guard sqlite3_open_v2(url.path, &connection.pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw LocalStoreError.sqlite("Unable to open local database")
        }
        sqlite3_busy_timeout(connection.pointer, 2_000)
        try Self.exec(connection.pointer, "PRAGMA journal_mode=WAL")
        try Self.exec(connection.pointer, "PRAGMA foreign_keys=ON")
        try Self.exec(connection.pointer, Self.schema)
        self.connection = connection
    }

// Direct builds only: reading outside the container needs a temporary-exception entitlement,
// which the App Store build does not have (and never had an unsandboxed predecessor).
#if !APP_STORE
    /// Builds before sandboxing kept the database in the real ~/Library/Application Support;
    /// the sandbox redirects that to the app container, so copy it over once.
    private static func migrateFromUnsandboxedLocation(to url: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return }
        let legacy = realHomeDirectory.appending(path: "Library/Application Support/NotiForward/noti-forward.sqlite")
        guard legacy.path != url.path, fileManager.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.copyItem(at: source, to: URL(fileURLWithPath: url.path + suffix))
        }
    }
#endif

    func loadSettings() throws -> (GeneralSettings, RuleConfiguration) {
        let general: GeneralSettings = try decodeSetting(key: "general") ?? GeneralSettings()
        let rules: RuleConfiguration = try decodeSetting(key: "rules") ?? .initial
        return (general, rules)
    }

    func save(general: GeneralSettings) throws { try encodeSetting(key: "general", value: general) }
    func save(rules: RuleConfiguration) throws { try encodeSetting(key: "rules", value: rules) }

    func enqueue(_ notification: CapturedNotification) throws {
        let data = try JSONEncoder.notiForward.encode(notification)
        try statement("INSERT OR IGNORE INTO pending_notifications(id,payload,created_at) VALUES(?,?,?)") { statement in
            bind(notification.id.uuidString, at: 1, to: statement)
            bind(data, at: 2, to: statement)
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        }
    }

    func pendingNotifications(limit: Int = 100) throws -> [CapturedNotification] {
        try blobs(sql: "SELECT payload FROM pending_notifications ORDER BY created_at LIMIT ?", limit: limit)
            .compactMap { try? JSONDecoder.notiForward.decode(CapturedNotification.self, from: $0) }
    }

    func removePending(id: UUID) throws {
        try statement("DELETE FROM pending_notifications WHERE id=?") { bind(id.uuidString, at: 1, to: $0) }
    }

    func syncCursor() throws -> Int64 {
        let value: Int64? = try decodeSetting(key: "notification_cursor")
        return value ?? 0
    }

    func saveSyncCursor(_ cursor: Int64) throws { try encodeSetting(key: "notification_cursor", value: cursor) }

    func purgePending(olderThan cutoff: Date) throws {
        try statement("DELETE FROM pending_notifications WHERE created_at < ?") { sqlite3_bind_double($0, 1, cutoff.timeIntervalSince1970) }
    }

    private func encodeSetting<T: Encodable>(key: String, value: T) throws {
        let data = try JSONEncoder.notiForward.encode(value)
        try statement("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { statement in
            bind(key, at: 1, to: statement)
            bind(data, at: 2, to: statement)
        }
    }

    private func decodeSetting<T: Decodable>(key: String) throws -> T? {
        guard let data = try blobs(sql: "SELECT value FROM settings WHERE key=?", textValue: key).first else { return nil }
        return try JSONDecoder.notiForward.decode(T.self, from: data)
    }

    private func blobs(sql: String, textValue: String? = nil, limit: Int? = nil) throws -> [Data] {
        guard let db else { throw LocalStoreError.sqlite("Database is closed") }
        var raw: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        if let textValue { bind(textValue, at: 1, to: statement) }
        if let limit { sqlite3_bind_int(statement, 1, Int32(limit)) }
        var result: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) {
            result.append(Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0))))
        }
        return result
    }

    private func statement(_ sql: String, bindValues: (OpaquePointer) throws -> Void) throws {
        guard let db else { throw LocalStoreError.sqlite("Database is closed") }
        var raw: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        try bindValues(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func lastError() -> LocalStoreError {
        .sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error")
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(error)
            throw LocalStoreError.sqlite(message)
        }
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value BLOB NOT NULL);
    CREATE TABLE IF NOT EXISTS pending_notifications(id TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at REAL NOT NULL);
    """
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
    guard let value else { sqlite3_bind_null(statement, index); return }
    sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
}

private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) {
    _ = value.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
    }
}
