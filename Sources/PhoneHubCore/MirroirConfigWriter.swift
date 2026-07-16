import Foundation

/// Writes/merges mirroir's per-user JSON config (`~/.mirroir-mcp/config.json`).
public enum MirroirConfigWriter {
    public static func configURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".mirroir-mcp/config.json")
    }

    /// Merge `screenDescriberMode` into the mirroir config file, preserving other keys.
    /// Creates `~/.mirroir-mcp` when missing. Atomic write of valid JSON.
    public static func applyScreenDescriberMode(
        _ mode: ScreenDescriberMode,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws {
        let dir = home.appendingPathComponent(".mirroir-mcp", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = configURL(home: home)
        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = object
        }
        root["screenDescriberMode"] = mode.rawValue

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}

/// Apply the user's chosen screen describer mode when spawning mirroir (iOS only).
/// No-op for androir / other servers. Failures are swallowed — spawn must not break.
public func prepareMirroirConfigForSpawn(
    serverName: String,
    mode: ScreenDescriberMode? = nil,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
) {
    guard serverName == "mirroir" else { return }
    let chosen = mode ?? LLMConfigStore().load().screenDescriberMode
    try? MirroirConfigWriter.applyScreenDescriberMode(chosen, home: home)
}
