import Foundation

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

    private static func prop(_ serial: String, _ key: String) -> String {
        guard isValidSerial(serial),
              let res = try? runTool("adb", adbArgs(serial: serial, "shell", "getprop", key)),
              res.exitCode == 0,
              let s = String(data: res.stdout, encoding: .utf8) else { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
