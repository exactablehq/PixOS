import Foundation
import CoreSyncEngine

print("\u{001B}[1m--- Running PixOS CoreSyncEngine Test Suite ---\u{001B}[0m")

// Test 1: SyncDatabase
do {
    print("[TEST 1/2] Testing SyncDatabase (SQLite3)...")
    let tempDir = FileManager.default.temporaryDirectory
    let testDB = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
    let db = SyncDatabase(customPath: testDB.path)

    let testFingerprint = "IMG_4200.HEIC_2097152_1700000000"
    assert(!db.isSynced(fingerprint: testFingerprint), "Fresh DB should not contain fingerprint")

    db.recordSynced(
        fingerprint: testFingerprint,
        filename: "IMG_4200.HEIC",
        fileSize: 2097152,
        mediaType: "photo",
        creationDate: Date(),
        pixelPath: "/sdcard/DCIM/iPhone/IMG_4200.HEIC",
        isMotionPhoto: false
    )

    assert(db.isSynced(fingerprint: testFingerprint), "DB should report fingerprint as synced")

    let all = db.getAllSyncedFingerprints()
    assert(all.contains(testFingerprint), "All fingerprints should contain recorded item")

    let stats = db.getStats()
    assert(stats.count == 1, "Stats count should be 1")
    assert(stats.totalBytes == 2097152, "Stats total bytes should match")
    assert(stats.lastSyncDate != nil, "Last sync date should be recorded")

    try? FileManager.default.removeItem(at: testDB)
    print("\u{001B}[32m✔ PASS:\u{001B}[0m SyncDatabase tests succeeded!")
}

// Test 2: MotionPhotoBuilder
do {
    print("[TEST 2/2] Testing MotionPhotoBuilder (XMP synthesis & multiplexing)...")
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Minimal valid JPEG SOI (0xFF, 0xD8) + EOI (0xFF, 0xD9)
    let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9]
    let jpegData = Data(jpegBytes)
    let videoData = "MOCK_LIVE_PHOTO_VIDEO_STREAM".data(using: .utf8)!

    let imageURL = tempDir.appendingPathComponent("sample.jpg")
    let videoURL = tempDir.appendingPathComponent("sample.mov")
    let outputURL = tempDir.appendingPathComponent("sample_motion.jpg")

    try jpegData.write(to: imageURL)
    try videoData.write(to: videoURL)

    try MotionPhotoBuilder.buildMotionPhoto(imageURL: imageURL, videoURL: videoURL, outputURL: outputURL)

    assert(FileManager.default.fileExists(atPath: outputURL.path), "Output motion photo should exist")
    let outputData = try Data(contentsOf: outputURL)
    assert(outputData.count > jpegData.count + videoData.count, "Output should contain JPEG + XMP + Video")

    let outputStr = String(data: outputData, encoding: .isoLatin1) ?? ""
    assert(outputStr.contains("Camera:MotionPhoto=\"1\""), "Should contain Camera:MotionPhoto tag")
    assert(outputStr.contains("GCamera:MicroVideoOffset=\"\(videoData.count)\""), "Should contain GCamera:MicroVideoOffset")
    assert(outputStr.contains("GCamera:MicroVideoPresentationTimestampUs="), "Should contain MicroVideoPresentationTimestampUs")

    try? FileManager.default.removeItem(at: tempDir)
    print("\u{001B}[32m✔ PASS:\u{001B}[0m MotionPhotoBuilder tests succeeded!")
}

print("\n\u{001B}[32m\u{001B}[1mALL TESTS PASSED SUCCESSFULLY! (2/2)\u{001B}[0m\n")
