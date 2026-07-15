import XCTest
@testable import PhoneHubCore

final class SkillsStatusTests: XCTestCase {
    func testMirroirSkillsInstalledTracksDirectoryExistence() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsStatusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertFalse(SkillsStatus.mirroirSkillsInstalled(home: home))

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".mirroir-mcp/skills", isDirectory: true),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(SkillsStatus.mirroirSkillsInstalled(home: home))
    }
}
