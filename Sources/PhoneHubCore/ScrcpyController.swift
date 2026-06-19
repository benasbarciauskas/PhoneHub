import CoreGraphics
import Foundation

public enum ScrcpyArgsError: Error, Equatable {
    case invalidSerial
}

public enum ScrcpyLaunchState: Equatable {
    case idle
    case invalidSerial
    case missingTool
    case failedToStart(String)
    case running(pid_t)
    case stopped
}

public func scrcpyArgs(serial: String,
                       x: Int,
                       y: Int,
                       width: Int,
                       height: Int,
                       title: String) throws -> [String] {
    guard isValidSerial(serial) else { throw ScrcpyArgsError.invalidSerial }
    return [
        "--window-borderless",
        "--window-x", String(x),
        "--window-y", String(y),
        "--window-width", String(width),
        "--window-height", String(height),
        "--window-title", title,
        "-s", serial
    ]
}

public final class ScrcpyController {
    private var processes: [String: Process] = [:]
    public private(set) var lastState: ScrcpyLaunchState = .idle

    public init() {}

    @discardableResult
    public func launch(serial: String, frame: CGRect) -> Process? {
        guard isValidSerial(serial) else {
            lastState = .invalidSerial
            return nil
        }
        guard let path = resolveTool("scrcpy") else {
            lastState = .missingTool
            return nil
        }

        stop(serial: serial)

        let args: [String]
        do {
            args = try scrcpyArgs(serial: serial,
                                  x: Int(frame.origin.x.rounded()),
                                  y: Int(frame.origin.y.rounded()),
                                  width: Int(frame.width.rounded()),
                                  height: Int(frame.height.rounded()),
                                  title: "PhoneHub \(serial)")
        } catch {
            lastState = .invalidSerial
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            processes[serial] = process
            lastState = .running(process.processIdentifier)
            return process
        } catch {
            lastState = .failedToStart(error.localizedDescription)
            return nil
        }
    }

    public func stop(serial: String) {
        guard let process = processes.removeValue(forKey: serial) else { return }
        if process.isRunning {
            process.terminate()
        }
        lastState = .stopped
    }
}
