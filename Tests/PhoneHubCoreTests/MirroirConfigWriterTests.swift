import XCTest
@testable import PhoneHubCore

final class MirroirConfigWriterTests: XCTestCase {
    func testApplyWritesModeIntoFreshConfig() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try MirroirConfigWriter.applyScreenDescriberMode(.ocr, home: home)

        let root = try loadConfig(home: home)
        XCTAssertEqual(root["screenDescriberMode"] as? String, "ocr")
        XCTAssertEqual(root.count, 1)
    }

    func testApplyMergesAndPreservesOtherKeys() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let dir = home.appendingPathComponent(".mirroir-mcp", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "yoloModelPath": "/custom/path.mlmodelc",
            "screenDescriberMode": "auto",
            "extraFlag": true
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: MirroirConfigWriter.configURL(home: home))

        try MirroirConfigWriter.applyScreenDescriberMode(.vision, home: home)

        let root = try loadConfig(home: home)
        XCTAssertEqual(root["screenDescriberMode"] as? String, "vision")
        XCTAssertEqual(root["yoloModelPath"] as? String, "/custom/path.mlmodelc")
        XCTAssertEqual(root["extraFlag"] as? Bool, true)
    }

    func testApplyProducesValidJSONForAllModes() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        for mode in ScreenDescriberMode.allCases {
            try MirroirConfigWriter.applyScreenDescriberMode(mode, home: home)
            let data = try Data(contentsOf: MirroirConfigWriter.configURL(home: home))
            let object = try JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(object as? [String: Any], mode.rawValue)
            let root = try loadConfig(home: home)
            XCTAssertEqual(root["screenDescriberMode"] as? String, mode.rawValue)
        }
    }

    func testPrepareMirroirConfigForSpawnIsIOSOnly() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        prepareMirroirConfigForSpawn(serverName: "androir", mode: .vision, home: home)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: MirroirConfigWriter.configURL(home: home).path)
        )

        prepareMirroirConfigForSpawn(serverName: "mirroir", mode: .ocr, home: home)
        let root = try loadConfig(home: home)
        XCTAssertEqual(root["screenDescriberMode"] as? String, "ocr")
    }

    // MARK: - helpers

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirroirConfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func loadConfig(home: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: MirroirConfigWriter.configURL(home: home))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
