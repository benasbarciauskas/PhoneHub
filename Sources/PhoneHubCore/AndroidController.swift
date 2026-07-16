import Foundation

public struct AndroidConnectError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum AndroidController {

    /// Discover connected Android devices via `adb`. Never throws on a missing tool.
    public static func discover() -> [Device] {
        guard let res = try? runTool("adb", ["devices", "-l"]),
              res.exitCode == 0,
              let text = String(data: res.stdout, encoding: .utf8) else { return [] }

        return parseAdbDevices(text).compactMap { row in
            guard isValidSerial(row.serial) else { return nil }
            let model = row.state == "device" ? prop(row.serial, "ro.product.model") : ""
            let os = row.state == "device" ? prop(row.serial, "ro.build.version.release") : ""
            return Device(id: row.serial, platform: .android,
                          model: model.isEmpty ? row.serial : model,
                          osVersion: os, status: row.state)
        }
    }

    /// Connect to an Android device over the network via `adb connect host:port`.
    /// Validates host:port first; never builds a shell string.
    public static func connect(hostPort: String) -> Result<String, AndroidConnectError> {
        let trimmed = hostPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHostPort(trimmed) else {
            return .failure(AndroidConnectError("Invalid host:port. Use e.g. 192.168.1.50:5555"))
        }
        let res: CommandResult
        do {
            res = try runTool("adb", ["connect", trimmed])
        } catch {
            return .failure(AndroidConnectError("adb not found — brew install android-platform-tools"))
        }
        let stdout = String(data: res.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stdout.isEmpty ? stderr : stdout
        let lower = message.lowercased()
        // Success: "connected to …" / "already connected to …". Failures often still exit 0.
        let ok = lower.contains("connected")
            && !lower.contains("failed")
            && !lower.contains("unable")
            && !lower.contains("error")
        if ok {
            return .success(message.isEmpty ? "Connected to \(trimmed)" : message)
        }
        return .failure(AndroidConnectError(
            message.isEmpty ? "Failed to connect to \(trimmed)" : message
        ))
    }

    private static func prop(_ serial: String, _ key: String) -> String {
        guard isValidSerial(serial),
              let res = try? runTool("adb", adbArgs(serial: serial, "shell", "getprop", key)),
              res.exitCode == 0,
              let s = String(data: res.stdout, encoding: .utf8) else { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
