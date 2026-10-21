import XCTest
@testable import CoreSyncEngine

final class MotionPhotoBuilderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testBuildMotionPhotoJPEG() throws {
        // Minimal JPEG SOI (0xFF, 0xD8) + EOI (0xFF, 0xD9)
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9])
        let videoData = "MOCK_VIDEO_STREAM_DATA".data(using: .utf8)!

        let imageURL = tempDir.appendingPathComponent("test.jpg")
        let videoURL = tempDir.appendingPathComponent("test.mov")
        let outputURL = tempDir.appendingPathComponent("output.jpg")

        try jpegData.write(to: imageURL)
        try videoData.write(to: videoURL)

        try MotionPhotoBuilder.buildMotionPhoto(imageURL: imageURL, videoURL: videoURL, outputURL: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let outputData = try Data(contentsOf: outputURL)

        // Verify output is larger than image + video
        XCTAssertGreaterThan(outputData.count, jpegData.count + videoData.count)

        // Verify XMP tags are present
        let str = String(data: outputData, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(str.contains("Camera:MotionPhoto=\"1\""))
        XCTAssertTrue(str.contains("GCamera:MicroVideoOffset=\"\(videoData.count)\""))
    }
}
