import Foundation

public enum SkillsStatus {
    public static func mirroirSkillsInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = home.appendingPathComponent(".mirroir-mcp/skills", isDirectory: true).path
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
