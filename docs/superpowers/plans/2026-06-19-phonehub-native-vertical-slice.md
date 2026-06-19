# PhoneHub Native Vertical Slice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first working slice of the native PhoneHub macOS app — launch, discover connected Android devices, show the focused device's live screen, click-to-tap on it, and screenshot — in the OLED-black design system.

**Architecture:** SwiftUI macOS app (SwiftPM, like sibling apps Mirror Deck / MacCare). Pure logic lives in a `PhoneHubCore` library target (unit-tested); SwiftUI views live in the `PhoneHub` executable target. Android control is direct via `adb` subprocess (screencap frames + `input tap`). iOS/WebDriverAgent is a later phase — not in this slice.

**Tech Stack:** Swift 5.9+, SwiftUI, Observation (`@Observable`, macOS 14+), Foundation `Process`, `adb` (Android Platform Tools), XCTest.

---

## File Structure

- `Package.swift` — SwiftPM manifest: `PhoneHubCore` (lib), `PhoneHub` (executable, SwiftUI), `PhoneHubCoreTests` (test). macOS 14 platform.
- `Sources/PhoneHubCore/Device.swift` — `Device` model + `Platform` enum.
- `Sources/PhoneHubCore/AdbParsing.swift` — pure parsers: `adb devices -l`, `getprop`, `wm size`.
- `Sources/PhoneHubCore/CoordinateMapper.swift` — pure view-point → device-pixel mapping (aspect-fit).
- `Sources/PhoneHubCore/Shell.swift` — minimal `Process` runner + `adbArgs` argv builders (pure).
- `Sources/PhoneHubCore/AndroidController.swift` — discovery, screencap frame, tap, screenshot (uses Shell + parsers).
- `Sources/PhoneHub/PhoneHubApp.swift` — `@main` SwiftUI App, single window.
- `Sources/PhoneHub/Theme.swift` — OLED design tokens + view modifiers.
- `Sources/PhoneHub/DeviceStore.swift` — `@Observable` store wrapping discovery + refresh + focus.
- `Sources/PhoneHub/Sidebar.swift` — device-row list.
- `Sources/PhoneHub/Stage.swift` — focused device live view + control rail.
- `Sources/PhoneHub/StreamView.swift` — renders frames, captures clicks → tap.
- `Tests/PhoneHubCoreTests/AdbParsingTests.swift`, `CoordinateMapperTests.swift`, `ShellTests.swift`.
- `build-app.sh`, `Info.plist` — package + sign the `.app`.
- Delete: `src/`, `main.py`, `requirements.txt`, `tests/` (Python MVP).

---

## Task 1: Retire Python MVP + SwiftPM skeleton

**Files:**
- Delete: `src/`, `main.py`, `requirements.txt`, `tests/`
- Create: `Package.swift`, `Sources/PhoneHubCore/Device.swift`, `Sources/PhoneHub/PhoneHubApp.swift`

- [ ] **Step 1: Remove the Python MVP**

```bash
cd "/Volumes/X10 Pro/Ruflo/projects/PhoneHub/.worktrees/native-foundation"
git rm -r src tests main.py requirements.txt
```

- [ ] **Step 2: Update `.gitignore` for Swift**

Append to `.gitignore`:

```gitignore
# Swift / SwiftPM
.build/
*.app/
.swiftpm/
PhoneHub.app/
```

- [ ] **Step 3: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PhoneHubCore"),
        .executableTarget(
            name: "PhoneHub",
            dependencies: ["PhoneHubCore"]
        ),
        .testTarget(
            name: "PhoneHubCoreTests",
            dependencies: ["PhoneHubCore"]
        ),
    ]
)
```

- [ ] **Step 4: Write `Sources/PhoneHubCore/Device.swift`**

```swift
import Foundation

public enum Platform: String, Sendable, Codable {
    case ios
    case android
}

public struct Device: Identifiable, Hashable, Sendable {
    public let id: String        // udid / serial
    public let platform: Platform
    public var model: String
    public var osVersion: String
    public var status: String    // "device", "unauthorized", "offline", ...

    public init(id: String, platform: Platform, model: String, osVersion: String, status: String) {
        self.id = id
        self.platform = platform
        self.model = model
        self.osVersion = osVersion
        self.status = status
    }

    public var isReady: Bool { status == "device" }
}
```

- [ ] **Step 5: Write a minimal `Sources/PhoneHub/PhoneHubApp.swift` (compiles, empty window)**

```swift
import SwiftUI

@main
struct PhoneHubApp: App {
    var body: some Scene {
        WindowGroup("PhoneHub") {
            Text("PhoneHub")
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
```

- [ ] **Step 6: Verify it builds**

Run:
```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build
```
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: retire Python MVP, scaffold SwiftPM PhoneHub app"
```

---

## Task 2: adb output parsers (TDD)

**Files:**
- Create: `Sources/PhoneHubCore/AdbParsing.swift`
- Test: `Tests/PhoneHubCoreTests/AdbParsingTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/PhoneHubCoreTests/AdbParsingTests.swift`:
```swift
import XCTest
@testable import PhoneHubCore

final class AdbParsingTests: XCTestCase {
    func testParseDevicesNormal() {
        let out = """
        List of devices attached
        emulator-5554\tdevice product:sdk model:Pixel_6 device:generic
        R3CT90\tunauthorized
        ZY223\toffline

        """
        let rows = parseAdbDevices(out)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].serial, "emulator-5554")
        XCTAssertEqual(rows[0].state, "device")
        XCTAssertEqual(rows[1].state, "unauthorized")
        XCTAssertEqual(rows[2].state, "offline")
    }

    func testParseDevicesEmpty() {
        let rows = parseAdbDevices("List of devices attached\n\n")
        XCTAssertTrue(rows.isEmpty)
    }

    func testParseDevicesSkipsDaemonChatter() {
        let out = """
        * daemon not running; starting now at tcp:5037 *
        * daemon started successfully *
        List of devices attached
        ZY223JR9XN\tdevice
        """
        let rows = parseAdbDevices(out)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].serial, "ZY223JR9XN")
    }

    func testParseWmSize() {
        XCTAssertEqual(parseWmSize("Physical size: 1080x2340"), CGSize(width: 1080, height: 2340))
        XCTAssertEqual(parseWmSize("Physical size: 1440x3088\nOverride size: 1080x2340"),
                       CGSize(width: 1080, height: 2340)) // override wins
        XCTAssertNil(parseWmSize("garbage"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift test --filter AdbParsingTests
```
Expected: FAIL — `parseAdbDevices`/`parseWmSize` not found.

- [ ] **Step 3: Write `Sources/PhoneHubCore/AdbParsing.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter AdbParsingTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneHubCore/AdbParsing.swift Tests/PhoneHubCoreTests/AdbParsingTests.swift
git commit -m "feat(core): adb devices + wm size parsers"
```

---

## Task 3: CoordinateMapper (TDD)

**Files:**
- Create: `Sources/PhoneHubCore/CoordinateMapper.swift`
- Test: `Tests/PhoneHubCoreTests/CoordinateMapperTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/PhoneHubCoreTests/CoordinateMapperTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import PhoneHubCore

final class CoordinateMapperTests: XCTestCase {
    // Device 1000x2000 (tall). View 500x500 → aspect-fit gives rendered 250x500,
    // letterboxed horizontally with 125pt bars on each side.
    func testCenterMapsToDeviceCenter() {
        let p = viewPointToDevicePoint(.init(x: 250, y: 250),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 500, accuracy: 0.5)
        XCTAssertEqual(p.y, 1000, accuracy: 0.5)
    }

    func testClickInLetterboxClampsToEdge() {
        // x=10 is inside the left letterbox bar (bar is 0..125) → clamps to device x 0.
        let p = viewPointToDevicePoint(.init(x: 10, y: 250),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
    }

    func testTopLeftOfImage() {
        // Rendered image left edge is at view x=125, top at y=0.
        let p = viewPointToDevicePoint(.init(x: 125, y: 0),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testDegenerateSizesReturnZero() {
        let p = viewPointToDevicePoint(.init(x: 5, y: 5),
                                       viewSize: .zero,
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p, .zero)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter CoordinateMapperTests
```
Expected: FAIL — `viewPointToDevicePoint` not found.

- [ ] **Step 3: Write `Sources/PhoneHubCore/CoordinateMapper.swift`**

```swift
import CoreGraphics

/// Map a click in the SwiftUI view's coordinate space to a device pixel,
/// accounting for aspect-fit letterboxing. Result is clamped to the device bounds.
public func viewPointToDevicePoint(_ point: CGPoint,
                                   viewSize: CGSize,
                                   deviceSize: CGSize) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0,
          deviceSize.width > 0, deviceSize.height > 0 else { return .zero }

    let scale = min(viewSize.width / deviceSize.width,
                    viewSize.height / deviceSize.height)
    let rendered = CGSize(width: deviceSize.width * scale,
                          height: deviceSize.height * scale)
    let offsetX = (viewSize.width - rendered.width) / 2
    let offsetY = (viewSize.height - rendered.height) / 2

    let deviceX = (point.x - offsetX) / scale
    let deviceY = (point.y - offsetY) / scale

    return CGPoint(x: min(max(deviceX, 0), deviceSize.width),
                   y: min(max(deviceY, 0), deviceSize.height))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter CoordinateMapperTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneHubCore/CoordinateMapper.swift Tests/PhoneHubCoreTests/CoordinateMapperTests.swift
git commit -m "feat(core): view-to-device coordinate mapper"
```

---

## Task 4: Shell runner + adb argv builders (TDD for builders)

**Files:**
- Create: `Sources/PhoneHubCore/Shell.swift`
- Test: `Tests/PhoneHubCoreTests/ShellTests.swift`

- [ ] **Step 1: Write the failing tests (argv builders are pure → testable)**

`Tests/PhoneHubCoreTests/ShellTests.swift`:
```swift
import XCTest
@testable import PhoneHubCore

final class ShellTests: XCTestCase {
    func testAdbArgsPrependsSerial() {
        XCTAssertEqual(adbArgs(serial: "ZY223", "shell", "input", "tap", "10", "20"),
                       ["-s", "ZY223", "shell", "input", "tap", "10", "20"])
    }

    func testTapArgs() {
        XCTAssertEqual(adbTapArgs(serial: "ZY223", x: 540, y: 1170),
                       ["-s", "ZY223", "shell", "input", "tap", "540", "1170"])
    }

    func testScreencapArgs() {
        XCTAssertEqual(adbScreencapArgs(serial: "ZY223"),
                       ["-s", "ZY223", "exec-out", "screencap", "-p"])
    }

    func testValidSerialRejectsInjection() {
        XCTAssertTrue(isValidSerial("emulator-5554"))
        XCTAssertTrue(isValidSerial("ZY223JR9XN"))
        XCTAssertFalse(isValidSerial("a b"))
        XCTAssertFalse(isValidSerial("a;rm -rf"))
        XCTAssertFalse(isValidSerial(""))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter ShellTests
```
Expected: FAIL — symbols not found.

- [ ] **Step 3: Write `Sources/PhoneHubCore/Shell.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter ShellTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneHubCore/Shell.swift Tests/PhoneHubCoreTests/ShellTests.swift
git commit -m "feat(core): shell runner + adb argv builders + serial validation"
```

---

## Task 5: AndroidController (discovery, frame, tap, screenshot)

**Files:**
- Create: `Sources/PhoneHubCore/AndroidController.swift`

This task wires the tested pieces to real `adb`. The pure parts are already covered; this glue is exercised in the manual smoke test (Task 10). No new unit test (would require a connected device or mocking `Process`, out of scope for the slice).

- [ ] **Step 1: Write `Sources/PhoneHubCore/AndroidController.swift`**

```swift
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
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneHubCore/AndroidController.swift
git commit -m "feat(core): AndroidController — discover, frame, tap, screenshot"
```

---

## Task 6: Theme (OLED design system)

**Files:**
- Create: `Sources/PhoneHub/Theme.swift`

- [ ] **Step 1: Write `Sources/PhoneHub/Theme.swift`**

```swift
import SwiftUI

/// OLED-black design system. Single source of truth for color, spacing, radius, motion.
enum Theme {
    // Color tokens
    static let bg        = Color(hex: 0x000000)
    static let surface   = Color(hex: 0x0B0B0D)
    static let elevated  = Color(hex: 0x1C1C1F)
    static let border    = Color(hex: 0x2A2A2E)
    static let text      = Color(hex: 0xF5F5F7)
    static let subtext   = Color(hex: 0x8A8A8E)
    static let accent    = Color(hex: 0x0A84FF)
    static let ok        = Color(hex: 0x30D158)
    static let warn      = Color(hex: 0xFFD60A)
    static let err       = Color(hex: 0xFF453A)

    // Spacing grid (4pt)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24

    // Radii
    static let rSm: CGFloat = 6
    static let rMd: CGFloat = 10
    static let rLg: CGFloat = 16

    // Motion — fast, purposeful (Emil Kowalski)
    static let focusSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)
    static let selection   = Animation.easeOut(duration: 0.16)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Card surface modifier used across the UI.
struct CardSurface: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Theme.elevated : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func cardSurface(elevated: Bool = false) -> some View { modifier(CardSurface(elevated: elevated)) }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneHub/Theme.swift
git commit -m "feat(ui): OLED design system theme tokens"
```

---

## Task 7: DeviceStore (@Observable)

**Files:**
- Create: `Sources/PhoneHub/DeviceStore.swift`

- [ ] **Step 1: Write `Sources/PhoneHub/DeviceStore.swift`**

```swift
import Foundation
import Observation
import PhoneHubCore

@Observable
@MainActor
final class DeviceStore {
    var devices: [Device] = []
    var focusedID: Device.ID?
    var toolMissing = false

    var focused: Device? { devices.first { $0.id == focusedID } }

    /// Re-run discovery off the main actor, then publish.
    func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = AndroidController.discover()       // Android only for this slice
            let missing = resolveTool("adb") == nil
            await MainActor.run {
                self.toolMissing = missing
                self.devices = found
                if self.focusedID == nil { self.focusedID = found.first?.id }
                else if !found.contains(where: { $0.id == self.focusedID }) {
                    self.focusedID = found.first?.id
                }
            }
        }
    }

    func focus(_ id: Device.ID) { focusedID = id }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneHub/DeviceStore.swift
git commit -m "feat(ui): DeviceStore observable wrapping discovery"
```

---

## Task 8: StreamView (live frames + click-to-tap)

**Files:**
- Create: `Sources/PhoneHub/StreamView.swift`

- [ ] **Step 1: Write `Sources/PhoneHub/StreamView.swift`**

```swift
import SwiftUI
import PhoneHubCore

/// Polls device frames (~2 fps) and forwards clicks as taps.
struct StreamView: View {
    let serial: String

    @State private var frame: NSImage?
    @State private var deviceSize: CGSize = .init(width: 1080, height: 2340)
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg
                if let frame {
                    Image(nsImage: frame)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let p = viewPointToDevicePoint(location, viewSize: geo.size, deviceSize: deviceSize)
                Task.detached { AndroidController.tap(serial: serial, x: Int(p.x), y: Int(p.y)) }
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .onChange(of: serial) { _, _ in restart() }
    }

    private func start() {
        if let s = AndroidController.screenSize(serial: serial) { deviceSize = s }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in poll() }
    }
    private func stop() { timer?.invalidate(); timer = nil }
    private func restart() { stop(); frame = nil; start() }

    private func poll() {
        let serial = serial
        Task.detached(priority: .userInitiated) {
            guard let data = AndroidController.captureFrame(serial: serial),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { self.frame = img }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneHub/StreamView.swift
git commit -m "feat(ui): StreamView live frame polling + click-to-tap"
```

---

## Task 9: Sidebar + Stage + wire the App

**Files:**
- Create: `Sources/PhoneHub/Sidebar.swift`, `Sources/PhoneHub/Stage.swift`
- Modify: `Sources/PhoneHub/PhoneHubApp.swift`

- [ ] **Step 1: Write `Sources/PhoneHub/Sidebar.swift`**

```swift
import SwiftUI
import PhoneHubCore

struct Sidebar: View {
    @Bindable var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Devices").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Theme.s3).padding(.top, Theme.s3)

            if store.toolMissing {
                Text("adb not found — `brew install android-platform-tools`")
                    .font(.caption).foregroundStyle(Theme.warn)
                    .padding(.horizontal, Theme.s3)
            }

            ScrollView {
                VStack(spacing: Theme.s1) {
                    ForEach(store.devices) { device in
                        DeviceRow(device: device, selected: device.id == store.focusedID)
                            .onTapGesture { withAnimation(Theme.selection) { store.focus(device.id) } }
                    }
                    if store.devices.isEmpty && !store.toolMissing {
                        Text("No devices connected").font(.caption)
                            .foregroundStyle(Theme.subtext).padding(.top, Theme.s4)
                    }
                }
                .padding(.horizontal, Theme.s2)
            }
        }
        .frame(width: 240)
        .background(Theme.surface)
    }
}

private struct DeviceRow: View {
    let device: Device
    let selected: Bool

    var statusColor: Color {
        switch device.status {
        case "device": return Theme.ok
        case "unauthorized": return Theme.warn
        default: return Theme.err
        }
    }

    var body: some View {
        HStack(spacing: Theme.s2) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.model).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(device.platform == .android ? "Android \(device.osVersion)" : "iOS \(device.osVersion)")
                    .font(.system(size: 11)).foregroundStyle(Theme.subtext)
            }
            Spacer()
        }
        .padding(.vertical, Theme.s2).padding(.horizontal, Theme.s3)
        .background(selected ? Theme.elevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
    }
}
```

- [ ] **Step 2: Write `Sources/PhoneHub/Stage.swift`**

```swift
import SwiftUI
import PhoneHubCore
import UniformTypeIdentifiers

struct Stage: View {
    @Bindable var store: DeviceStore

    var body: some View {
        ZStack {
            Theme.bg
            if let device = store.focused, device.isReady {
                VStack(spacing: Theme.s3) {
                    HStack {
                        Text(device.model).font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Button { saveScreenshot(device.id) } label: {
                            Label("Screenshot", systemImage: "camera")
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    StreamView(serial: device.id)
                        .id(device.id)
                        .cardSurface()
                }
                .padding(Theme.s6)
                .transition(.opacity)
            } else {
                Text(store.focused == nil ? "Select a device" : "Device not ready")
                    .foregroundStyle(Theme.subtext)
            }
        }
        .animation(Theme.focusSpring, value: store.focusedID)
    }

    private func saveScreenshot(_ serial: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(serial)-\(Int(Date().timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached { AndroidController.saveScreenshot(serial: serial, to: url) }
        }
    }
}
```

- [ ] **Step 3: Rewrite `Sources/PhoneHub/PhoneHubApp.swift`**

```swift
import SwiftUI

@main
struct PhoneHubApp: App {
    @State private var store = DeviceStore()

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store)
                Divider().overlay(Theme.border)
                Stage(store: store)
            }
            .frame(minWidth: 980, minHeight: 640)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .onAppear { store.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 4: Verify it builds**

Run:
```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 5: Run the full test suite**

Run:
```bash
swift test
```
Expected: all tests PASS (AdbParsing 4, CoordinateMapper 4, Shell 4).

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneHub/Sidebar.swift Sources/PhoneHub/Stage.swift Sources/PhoneHub/PhoneHubApp.swift
git commit -m "feat(ui): sidebar + stage + wire command-center window"
```

---

## Task 10: Package as .app + manual smoke verification

**Files:**
- Create: `build-app.sh`, `Info.plist`
- Modify: `README.md`

- [ ] **Step 1: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PhoneHub</string>
    <key>CFBundleDisplayName</key><string>PhoneHub</string>
    <key>CFBundleIdentifier</key><string>com.benas.phonehub</string>
    <key>CFBundleExecutable</key><string>PhoneHub</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Write `build-app.sh`**

```bash
#!/bin/bash
# Build PhoneHub.app — native SwiftUI device-control dashboard.
set -euo pipefail
cd "$(dirname "$0")"

# Use Command Line Tools toolchain to avoid the Xcode license gate (matches sibling apps).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

echo "→ Compiling (release) ..."
swift build -c release

APP="PhoneHub.app"
BIN="PhoneHub"
CONTENTS="${APP}/Contents"

echo "→ Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp ".build/release/${BIN}" "${CONTENTS}/MacOS/${BIN}"
cp Info.plist "${CONTENTS}/Info.plist"

echo "→ Ad-hoc signing ..."
codesign --force --deep --sign - "${APP}"

echo "✓ Built ${APP}"
echo "  Run: open ${APP}   (or install: cp -r ${APP} /Applications/)"
```

```bash
chmod +x build-app.sh
```

- [ ] **Step 3: Build the app bundle**

Run:
```bash
./build-app.sh
```
Expected: `✓ Built PhoneHub.app`

- [ ] **Step 4: Manual smoke test (requires one Android with USB debugging on)**

Connect an Android phone (USB debugging enabled, authorize the Mac). Then:
```bash
open PhoneHub.app
```
Verify, in order:
1. Window opens, dark/OLED, sidebar + empty stage.
2. The phone appears in the sidebar with a green dot, model + Android version.
3. Click it → stage shows the live screen (updates ~2×/sec).
4. Click somewhere on the live screen → the phone responds at that spot.
5. Click **Screenshot** → save dialog → PNG is written and opens correctly.

If no Android is available, at minimum verify the window renders, shows "adb not found" only when adb is truly absent, and shows "No devices connected" with adb present and nothing plugged in.

- [ ] **Step 5: Update `README.md`** (replace the Python-era Setup section)

Replace the `## Setup` section with:
```markdown
## Build & run

Requires macOS 14+, Swift toolchain (Command Line Tools or Xcode), and
`android-platform-tools` for Android control:

```bash
brew install android-platform-tools   # provides adb
./build-app.sh                         # builds PhoneHub.app
open PhoneHub.app
```

Connect an Android phone with USB debugging enabled and authorize the Mac.
The device appears in the sidebar; click it to see and control its live screen.

iOS support (WebDriverAgent) is a later phase.

## Tests

```bash
swift test
```
```

- [ ] **Step 6: Commit**

```bash
git add build-app.sh Info.plist README.md
git commit -m "build: PhoneHub.app packaging + smoke-test docs"
```

---

## Self-Review

**Spec coverage:**
- §1 scope (manual, own devices, retire Python) → Task 1 (retire) + overall. ✓
- §2 components: DeviceStore→T7, WDAClient→deferred (noted), AndroidController→T5, StreamView→T8, Sidebar/Stage→T9. ✓ (WDAClient is the next phase, per spec §5/§6 deferral.)
- §3 data flow → T7+T8+T9 wiring. ✓
- §4 coordinate mapping → T3 (pure + tested). ✓
- §5 WDA setup → deferred (spec §6 defers it). ✓
- §6 vertical slice (Android end-to-end) → T5–T10. ✓
- §7 design system → T6. ✓
- §8 packaging → T10. ✓
- §9 errors (tool missing banner, no crash) → T7 `toolMissing`, T5 graceful discover, Sidebar banner. ✓
- §10 testing (coord math, discovery parse) → T2/T3/T4 tests. MJPEG parser is iOS-phase (Android uses PNG via NSImage), so no MJPEG test in this slice — noted. ✓
- §11 process → worktree, ship on green. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Type consistency:** `Device.id` (serial) used consistently; `AndroidController` method names (`discover`, `screenSize`, `captureFrame`, `tap`, `saveScreenshot`) match across T5/T7/T8/T9; `viewPointToDevicePoint` signature consistent T3↔T8; `adbArgs`/`adbTapArgs`/`adbScreencapArgs` consistent T4↔T5; Theme tokens consistent T6↔T8/T9. ✓

**Note:** MJPEG frame parser (spec §10) belongs to the iOS/WDA phase (Android frames are PNG decoded by `NSImage`), so it is intentionally absent from this slice's tests.
