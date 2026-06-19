import Foundation

/// Strict serial/identifier charset — guards every value reaching a subprocess.
private let serialAllowed = CharacterSet(charactersIn:
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_-")

public func isValidSerial(_ s: String) -> Bool {
    guard !s.isEmpty, s.count <= 128 else { return false }
    return s.unicodeScalars.allSatisfy { serialAllowed.contains($0) }
}

public func adbArgs(serial: String, _ rest: String...) -> [String] {
    ["-s", serial] + rest
}

public func adbTapArgs(serial: String, x: Int, y: Int) -> [String] {
    ["-s", serial, "shell", "input", "tap", String(x), String(y)]
}

public func adbScreencapArgs(serial: String) -> [String] {
    ["-s", serial, "exec-out", "screencap", "-p"]
}

public struct CommandResult {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String
}

public enum ShellError: Error { case toolNotFound(String) }

/// Resolve a tool on the common Homebrew + system paths (GUI apps don't inherit a login PATH).
public func resolveTool(_ name: String) -> String? {
    let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// Run a tool with an argv list (never a shell string). Binary-safe stdout.
public func runTool(_ name: String, _ args: [String], timeout: TimeInterval = 30) throws -> CommandResult {
    guard let path = resolveTool(name) else { throw ShellError.toolNotFound(name) }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let out = Pipe(); let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    try proc.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return CommandResult(exitCode: proc.terminationStatus,
                         stdout: outData,
                         stderr: String(data: errData, encoding: .utf8) ?? "")
}
