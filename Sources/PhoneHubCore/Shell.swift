import Darwin
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

public struct CommandResult {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String
}

public enum ShellError: Error { case toolNotFound(String) }

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

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
    let exitSemaphore = DispatchSemaphore(value: 0)
    proc.terminationHandler = { _ in exitSemaphore.signal() }
    try proc.run()

    let readGroup = DispatchGroup()
    let outData = LockedData()
    let errData = LockedData()

    readGroup.enter()
    DispatchQueue.global(qos: .utility).async {
        outData.set(out.fileHandleForReading.readDataToEndOfFile())
        readGroup.leave()
    }

    readGroup.enter()
    DispatchQueue.global(qos: .utility).async {
        errData.set(err.fileHandleForReading.readDataToEndOfFile())
        readGroup.leave()
    }

    var timedOut = false
    if exitSemaphore.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        proc.terminate()
        if exitSemaphore.wait(timeout: .now() + 1) == .timedOut, proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }
    }

    readGroup.wait()

    if timedOut {
        var stderr = String(data: errData.data, encoding: .utf8) ?? ""
        if !stderr.isEmpty, !stderr.hasSuffix("\n") { stderr += "\n" }
        stderr += "timed out"
        return CommandResult(exitCode: -1,
                             stdout: outData.data,
                             stderr: stderr)
    }

    return CommandResult(exitCode: proc.terminationStatus,
                         stdout: outData.data,
                         stderr: String(data: errData.data, encoding: .utf8) ?? "")
}
