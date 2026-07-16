import XCTest
@testable import PhoneHubCore

final class DetectionStatusTests: XCTestCase {
    func testYoloModelInstalledRequiresMlmodelcUnderModels() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetectionStatus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertFalse(DetectionStatus.yoloModelInstalled(home: home))
        XCTAssertTrue(
            DetectionStatus.elementDetectionLine(home: home)
                .contains("not installed")
        )

        let models = home.appendingPathComponent(".mirroir-mcp/models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        XCTAssertFalse(DetectionStatus.yoloModelInstalled(home: home))

        // .mlmodelc is a Core ML package directory (or file); either counts.
        let bundle = models.appendingPathComponent("yolo.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertTrue(DetectionStatus.yoloModelInstalled(home: home))
        XCTAssertTrue(
            DetectionStatus.elementDetectionLine(home: home).contains("installed ✓")
        )
    }

    func testVisionDescriberHintIsStaticGuidance() {
        XCTAssertTrue(DetectionStatus.visionDescriberHint.contains("embacle-ffi"))
        XCTAssertTrue(DetectionStatus.visionDescriberHint.contains("Vision"))
    }
}
