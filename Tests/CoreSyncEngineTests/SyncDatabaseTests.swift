import XCTest
@testable import CoreSyncEngine

final class SyncDatabaseTests: XCTestCase {
    var tempDBURL: URL!
    var database: SyncDatabase!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempDBURL = tempDir.appendingPathComponent("test_sync_\(UUID().uuidString).db")
        database = SyncDatabase(customPath: tempDBURL.path)
    }

    override func tearDown() {
        database = nil
        try? FileManager.default.removeItem(at: tempDBURL)
        super.tearDown()
    }

    func testRecordAndCheckSync() {
        let fingerprint = "IMG_0001.HEIC_1048576_1600000000"
        XCTAssertFalse(database.isSynced(fingerprint: fingerprint))

        database.recordSynced(
            fingerprint: fingerprint,
            filename: "IMG_0001.HEIC",
            fileSize: 1048576,
            mediaType: "photo",
            creationDate: Date(),
            pixelPath: "/sdcard/DCIM/iPhone/IMG_0001.HEIC",
            isMotionPhoto: false
        )

        XCTAssertTrue(database.isSynced(fingerprint: fingerprint))

        let all = database.getAllSyncedFingerprints()
        XCTAssertTrue(all.contains(fingerprint))

        let stats = database.getStats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.totalBytes, 1048576)
        XCTAssertNotNil(stats.lastSyncDate)
    }

    func testMarkDeletedFromiPhone() {
        let fingerprint = "IMG_0002.MOV_5242880_1600000001"
        database.recordSynced(
            fingerprint: fingerprint,
            filename: "IMG_0002.MOV",
            fileSize: 5242880,
            mediaType: "video",
            creationDate: Date(),
            pixelPath: "/sdcard/DCIM/iPhone/IMG_0002.MOV",
            isMotionPhoto: false
        )

        database.markDeletedFromiPhone(fingerprint: fingerprint)
        XCTAssertTrue(database.isSynced(fingerprint: fingerprint))
    }
}
