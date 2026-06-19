import Foundation
import CoreGraphics

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

    /// Native screen size in pixels (Override wins over Physical).
    public static func screenSize(serial: String) -> CGSize? {
        guard isValidSerial(serial),
              let res = try? runTool("adb", adbArgs(serial: serial, "shell", "wm", "size")),
              res.exitCode == 0,
              let s = String(data: res.stdout, encoding: .utf8) else { return nil }
        return parseWmSize(s)
    }

    /// Capture a PNG frame of the device screen as raw bytes.
    public static func captureFrame(serial: String) -> Data? {
        guard isValidSerial(serial),
              let res = try? runTool("adb", adbScreencapArgs(serial: serial)),
              res.exitCode == 0, !res.stdout.isEmpty else { return nil }
        return res.stdout
    }

    /// Tap at device pixel coordinates.
    @discardableResult
    public static func tap(serial: String, x: Int, y: Int) -> Bool {
        guard isValidSerial(serial),
              let res = try? runTool("adb", adbTapArgs(serial: serial, x: x, y: y)) else { return false }
        return res.exitCode == 0
    }

    /// Save a screenshot PNG to `url`. Returns success.
    @discardableResult
    public static func saveScreenshot(serial: String, to url: URL) -> Bool {
        guard let data = captureFrame(serial: serial) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
