import Foundation
import SQLite3

public final class SyncDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbPath: String
    private let lock = NSLock()

    public init(customPath: String? = nil) {
        if let customPath = customPath {
            self.dbPath = customPath
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dir = home.appendingPathComponent(".pixos", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.dbPath = dir.appendingPathComponent("sync_state.db").path
        }
        openDatabase()
        createTable()
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    private func openDatabase() {
        lock.lock()
        defer { lock.unlock() }
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Error opening database \(dbPath): \(errmsg)")
        }
    }

    private func createTable() {
        lock.lock()
        defer { lock.unlock() }
        let createSQL = """
        CREATE TABLE IF NOT EXISTS synced_media (
            fingerprint TEXT PRIMARY KEY,
            filename TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            media_type TEXT,
            creation_date TEXT,
            pixel_path TEXT,
            synced_at TEXT NOT NULL,
            is_motion_photo INTEGER DEFAULT 0,
            deleted_from_iphone INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_filename ON synced_media(filename);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            print("Error creating table: \(error)")
            sqlite3_free(errMsg)
        }
    }

    public func isSynced(fingerprint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let query = "SELECT 1 FROM synced_media WHERE fingerprint = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (fingerprint as NSString).utf8String, -1, nil)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    public func getAllSyncedFingerprints() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        var result = Set<String>()
        let query = "SELECT fingerprint FROM synced_media;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return result
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                result.insert(String(cString: cStr))
            }
        }
        return result
    }

    public func recordSynced(
        fingerprint: String,
        filename: String,
        fileSize: Int64,
        mediaType: String,
        creationDate: Date?,
        pixelPath: String,
        isMotionPhoto: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        let insertSQL = """
        INSERT OR REPLACE INTO synced_media 
        (fingerprint, filename, file_size, media_type, creation_date, pixel_path, synced_at, is_motion_photo, deleted_from_iphone)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        let isoFormatter = ISO8601DateFormatter()
        let nowString = isoFormatter.string(from: Date())
        let dateString = creationDate.map { isoFormatter.string(from: $0) } ?? ""

        sqlite3_bind_text(stmt, 1, (fingerprint as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (filename as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, fileSize)
        sqlite3_bind_text(stmt, 4, (mediaType as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (dateString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (pixelPath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (nowString as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 8, isMotionPhoto ? 1 : 0)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Failed to record synced media: \(errmsg)")
        }
    }

    public func markDeletedFromiPhone(fingerprint: String) {
        lock.lock()
        defer { lock.unlock() }
        let updateSQL = "UPDATE synced_media SET deleted_from_iphone = 1 WHERE fingerprint = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (fingerprint as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    public func getStats() -> (count: Int, totalBytes: Int64, lastSyncDate: Date?) {
        lock.lock()
        defer { lock.unlock() }
        let query = "SELECT COUNT(*), COALESCE(SUM(file_size), 0), MAX(synced_at) FROM synced_media;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return (0, 0, nil)
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let count = Int(sqlite3_column_int(stmt, 0))
            let totalBytes = sqlite3_column_int64(stmt, 1)
            var lastDate: Date? = nil
            if let dateStr = sqlite3_column_text(stmt, 2) {
                let isoFormatter = ISO8601DateFormatter()
                lastDate = isoFormatter.date(from: String(cString: dateStr))
            }
            return (count, totalBytes, lastDate)
        }
        return (0, 0, nil)
    }
}
