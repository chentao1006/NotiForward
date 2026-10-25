import AppKit
import CryptoKit
import Foundation
import SQLite3

enum NotificationDatabaseError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return L("Notification database not found")
        case .permissionDenied: return L("Notification folder access is required")
        case .sqlite(let message): return message
        }
    }
}

private final class NotificationSQLiteConnection: @unchecked Sendable {
    var pointer: OpaquePointer?
    deinit { if let pointer { sqlite3_close(pointer) } }
}

actor NotificationDatabaseReader {
    nonisolated let databasePath: String
    private let connection: NotificationSQLiteConnection
    private var db: OpaquePointer? { connection.pointer }
    private let appleEpochOffset = 978_307_200.0

    /// `folder` is the granted group.com.apple.usernoted folder; its security scope must be active.
    init(folder: URL) throws {
        let connection = NotificationSQLiteConnection()
        let candidates = ["db2/db", "db/db"].map { folder.appending(path: $0).path }
        guard let path = candidates.first(where: FileManager.default.fileExists(atPath:)) else {
            throw NotificationDatabaseError.notFound
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw NotificationDatabaseError.permissionDenied
        }
        databasePath = path
        let uri = "file:\(path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &connection.pointer, flags, nil) == SQLITE_OK else {
            let code = connection.pointer.map(sqlite3_errcode) ?? SQLITE_CANTOPEN
            let message = connection.pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let pointer = connection.pointer { sqlite3_close(pointer) }
            connection.pointer = nil
            if code == SQLITE_AUTH || code == SQLITE_PERM || code == SQLITE_CANTOPEN {
                throw NotificationDatabaseError.permissionDenied
            }
            throw NotificationDatabaseError.sqlite(message)
        }
        sqlite3_busy_timeout(connection.pointer, 1_000)
        self.connection = connection
    }

    func maximumRecordID() throws -> Int64 {
        guard let db else { throw NotificationDatabaseError.permissionDenied }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT coalesce(max(rec_id),0) FROM record", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw error() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw error() }
        return sqlite3_column_int64(statement, 0)
    }

    func records(after cursor: Int64, limit: Int = 500) throws -> [CapturedNotification] {
        guard let db else { throw NotificationDatabaseError.permissionDenied }
        let sql = "SELECT r.rec_id,coalesce(a.identifier,''),r.uuid,r.data,r.delivered_date FROM record r LEFT JOIN app a ON a.app_id=r.app_id WHERE r.rec_id>? ORDER BY r.rec_id ASC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cursor)
        sqlite3_bind_int(statement, 2, Int32(limit))
        var result: [CapturedNotification] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recordID = sqlite3_column_int64(statement, 0)
            let bundleID = string(statement, 1)
            guard let data = blob(statement, 3) else { continue }
            let fields = decode(data)
            let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4) + appleEpochOffset)
            let id = uuid(statement, 2) ?? stableID(bundleID: bundleID, recordID: recordID, date: date)
            result.append(CapturedNotification(
                id: id,
                databaseID: recordID,
                sourceBundleID: bundleID,
                sourceAppName: appName(bundleID: bundleID),
                title: fields.title,
                subtitle: fields.subtitle,
                body: fields.body,
                originalDate: date,
                capturedDate: Date(),
                openURL: openURL(bundleID: bundleID)
            ))
        }
        return result
    }

    private func decode(_ data: Data) -> (title: String, subtitle: String, body: String) {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = root as? [String: Any] else { return ("", "", "") }
        let request = dictionary["req"] as? [String: Any] ?? dictionary
        func value(_ keys: [String]) -> String {
            keys.lazy.compactMap { request[$0] as? String }.first ?? ""
        }
        return (value(["titl", "title"]), value(["subt", "subtitle"]), value(["body"]))
    }

    private var apps: [String: (name: String, openURL: String?)] = [:]

    private func app(bundleID: String) -> (name: String, openURL: String?) {
        if let cached = apps[bundleID] { return cached }
        let app = CatalogApp.resolve(bundleID: bundleID)
        let scheme = AppURLScheme.preferred(bundleID: bundleID, schemes: app.urlSchemes)
        let resolved = (name: app.name, openURL: scheme.map { "\($0)://" })
        apps[bundleID] = resolved
        return resolved
    }

    private func appName(bundleID: String) -> String { app(bundleID: bundleID).name }
    private func openURL(bundleID: String) -> String? { app(bundleID: bundleID).openURL }

    private func stableID(bundleID: String, recordID: Int64, date: Date) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(bundleID)|\(recordID)|\(date.timeIntervalSince1970)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }

    private func uuid(_ statement: OpaquePointer, _ index: Int32) -> UUID? {
        guard let data = blob(statement, index), data.count == 16 else { return nil }
        let b = [UInt8](data)
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }

    private func blob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private func error() -> NotificationDatabaseError {
        guard let db else { return .permissionDenied }
        switch sqlite3_errcode(db) {
        case SQLITE_AUTH, SQLITE_PERM, SQLITE_CANTOPEN: return .permissionDenied
        default: return .sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }
}

