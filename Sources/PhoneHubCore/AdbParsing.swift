import Foundation
import CoreGraphics

public struct AdbDeviceRow: Equatable {
    public let serial: String
    public let state: String
}

/// Parse `adb devices -l` output into (serial, state) rows.
public func parseAdbDevices(_ output: String) -> [AdbDeviceRow] {
    var rows: [AdbDeviceRow] = []
    for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if line.hasPrefix("List of devices") { continue }
        if line.hasPrefix("*") { continue }   // daemon chatter
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { continue }
        rows.append(AdbDeviceRow(serial: String(fields[0]), state: String(fields[1])))
    }
    return rows
}

/// Parse `adb shell wm size`. An Override size, when present, wins.
public func parseWmSize(_ output: String) -> CGSize? {
    var physical: CGSize?
    var override: CGSize?
    for raw in output.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = line.firstIndex(of: ":") else { continue }
        let label = line[..<colon].lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { continue }
        let size = CGSize(width: w, height: h)
        if label.contains("override") { override = size }
        else if label.contains("physical") { physical = size }
    }
    return override ?? physical
}
