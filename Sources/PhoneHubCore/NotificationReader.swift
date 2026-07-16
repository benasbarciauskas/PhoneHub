import Foundation

/// A single active notification from an Android device (read-only display).
public struct PhoneNotification: Equatable, Identifiable, Sendable {
    public let id: String
    public let package: String
    public let title: String
    public let text: String
    public let whenMs: Int64?

    public init(package: String, title: String, text: String, whenMs: Int64? = nil, id: String? = nil) {
        self.package = package
        self.title = title
        self.text = text
        self.whenMs = whenMs
        // Stable-enough identity for list diffs; dumpsys has no guaranteed unique key across formats.
        self.id = id ?? "\(package)|\(title)|\(text)|\(whenMs.map(String.init) ?? "")"
    }
}

/// Read Android notifications via `adb shell dumpsys notification`.
/// Parser is pure (dumpsys text → [PhoneNotification]); adb call is thin.
public enum NotificationReader {

    /// Fetch active notifications for an Android device. Empty on bad serial / tool failure / empty dump.
    public static func fetch(serial: String) -> [PhoneNotification] {
        guard isValidSerial(serial) else { return [] }
        guard let res = try? runTool(
            "adb",
            adbArgs(serial: serial, "shell", "dumpsys", "notification", "--noredact"),
            timeout: 15
        ), res.exitCode == 0,
           let text = String(data: res.stdout, encoding: .utf8) else {
            // Fallback without --noredact (older platforms may reject the flag).
            guard let res = try? runTool(
                "adb",
                adbArgs(serial: serial, "shell", "dumpsys", "notification"),
                timeout: 15
            ), res.exitCode == 0,
               let text = String(data: res.stdout, encoding: .utf8) else {
                return []
            }
            return parseDumpsysNotifications(text)
        }
        return parseDumpsysNotifications(text)
    }
}

// MARK: - Pure parser

/// Parse `dumpsys notification` / `--noredact` output into notifications.
/// Best-effort over NotificationRecord blocks; tolerates format variance.
public func parseDumpsysNotifications(_ dumpsys: String) -> [PhoneNotification] {
    guard !dumpsys.isEmpty else { return [] }

    let blocks = splitNotificationRecords(dumpsys)
    guard !blocks.isEmpty else { return [] }

    var results: [PhoneNotification] = []
    results.reserveCapacity(blocks.count)

    for block in blocks {
        guard let parsed = parseNotificationRecord(block) else { continue }
        results.append(parsed)
    }
    return results
}

/// Split dumpsys text into NotificationRecord body strings (content after the header line).
private func splitNotificationRecords(_ text: String) -> [String] {
    // Match lines that start a record: "NotificationRecord(...)" possibly indented.
    // Also "  NotificationRecord(0x...:" style from various API levels.
    let pattern = #"(?m)^[ \t]*NotificationRecord\b[^\n]*\n"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    let matches = regex.matches(in: text, range: full)
    guard !matches.isEmpty else { return [] }

    var blocks: [String] = []
    for (i, match) in matches.enumerated() {
        let start = match.range.location + match.range.length
        let end: Int
        if i + 1 < matches.count {
            end = matches[i + 1].range.location
        } else {
            end = ns.length
        }
        guard end > start else { continue }
        let block = ns.substring(with: NSRange(location: start, length: end - start))
        blocks.append(block)
    }
    return blocks
}

private func parseNotificationRecord(_ block: String) -> PhoneNotification? {
    let pkg = extractPackage(block)
    // Skip empty/unusable records (no package and no title/text).
    let title = extractExtraString(block, key: "android.title") ?? ""
    let text = extractExtraString(block, key: "android.text")
        ?? extractExtraString(block, key: "android.bigText")
        ?? ""
    let whenMs = extractWhenMs(block)

    guard let pkg, !pkg.isEmpty else {
        // Some records bury pkg only in opPkg= — still require something usable.
        return nil
    }
    // Skip records with neither title nor text (system noise / group summaries often empty).
    if title.isEmpty && text.isEmpty { return nil }

    return PhoneNotification(package: pkg, title: title, text: text, whenMs: whenMs)
}

/// Extract package: `pkg=com.example.app` preferred, else `opPkg=...`.
private func extractPackage(_ block: String) -> String? {
    if let pkg = firstCapture(in: block, pattern: #"\bpkg=([A-Za-z0-9_.]+)"#) {
        return pkg
    }
    if let op = firstCapture(in: block, pattern: #"\bopPkg=([A-Za-z0-9_.]+)"#) {
        return op
    }
    // Header form: NotificationRecord(... PackageUserKey{com.example/0} ...) — rare fallback.
    if let fromKey = firstCapture(in: block, pattern: #"PackageUserKey\{([A-Za-z0-9_.]+)/"#) {
        return fromKey
    }
    return nil
}

/// Extract `android.title=String (…)` / `android.text=String (…)` style extras.
/// Also tolerates redacted `android.title=***` (returns empty) and bare `android.title=foo`.
private func extractExtraString(_ block: String, key: String) -> String? {
    let escaped = NSRegularExpression.escapedPattern(for: key)

    // Preferred: android.title=String (Bring The Rain)
    // dumpsys uses "Type (value)"; values rarely nest parens. Match to closing ).
    if let m = firstCapture(
        in: block,
        pattern: "\(escaped)=(?:String|CharSequence)\\s*\\((.*)\\)"
    ) {
        let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Redacted: android.title=***
    if firstCapture(in: block, pattern: "\(escaped)=(\\*{2,})") != nil {
        return nil
    }

    // Bare / other: android.title=SomeValue (no type wrapper), stop at whitespace or end of line
    if let bare = firstCapture(in: block, pattern: "\(escaped)=([^\\s\\n]+)") {
        if bare == "null" || bare.hasPrefix("***") { return nil }
        // Skip type-only tokens we already handled above
        if bare == "String" || bare == "CharSequence" || bare == "Boolean" || bare == "Integer" {
            return nil
        }
        return bare
    }

    return nil
}

private func extractWhenMs(_ block: String) -> Int64? {
    // postTime=1710000000000 or when=1710000000000
    if let s = firstCapture(in: block, pattern: #"\bpostTime=(\d+)"#), let v = Int64(s) {
        return v
    }
    if let s = firstCapture(in: block, pattern: #"\bwhen=(\d+)"#), let v = Int64(s) {
        return v
    }
    return nil
}

private func firstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = regex.firstMatch(in: text, range: range),
          match.numberOfRanges >= 2,
          match.range(at: 1).location != NSNotFound else {
        return nil
    }
    return ns.substring(with: match.range(at: 1))
}
