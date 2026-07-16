import Foundation

/// Status lines for mirroir's advanced detectors (YOLO element detection, vision describer).
/// Pure filesystem checks with injectable `home` for tests.
public enum DetectionStatus {
    /// True when `~/.mirroir-mcp/models` contains a `.mlmodelc` bundle (file or directory).
    public static func yoloModelInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        let models = home.appendingPathComponent(".mirroir-mcp/models", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: models,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return contents.contains { $0.pathExtension == "mlmodelc" }
    }

    public static func elementDetectionLine(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> String {
        if yoloModelInstalled(home: home, fileManager: fileManager) {
            return "Element detection (YOLO): installed ✓"
        }
        return "Element detection (YOLO): not installed — add a .mlmodelc to ~/.mirroir-mcp/models"
    }

    /// Best-effort note: embacle-ffi linkage can't be probed from PhoneHub.
    public static let visionDescriberHint =
        "Vision describer: set mode to Vision (requires embacle-ffi in mirroir)"
}
