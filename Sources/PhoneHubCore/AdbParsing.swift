import Foundation

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
