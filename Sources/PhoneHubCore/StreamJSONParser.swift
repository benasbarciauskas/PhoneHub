import Foundation

/// A digested event extracted from one line of `claude --output-format stream-json`.
public enum StreamEvent: Equatable {
    case system(subtype: String, sessionId: String?)  // init carries the session id
    case assistantText(String)          // model said something to the user
    case needInput(question: String)    // model emitted `NEED_INPUT: <question>`
    case toolUse(name: String, summary: String, rawInput: String) // tool arguments as compact JSON
    case toolResult(String)             // result of a tool call
    case result(subtype: String, text: String?, sessionId: String?) // final result / error; result events re-advertise session_id
    case ignored                        // a line we don't surface
}

/// How a parsed event should appear in the live UI.
public struct StreamUpdate: Equatable {
    public var logLine: String?         // appended to the scrollable log
    public var currentAction: String?   // replaces the one-line status
    public var finished: Bool           // run ended (result event)
    public var failed: Bool             // result event reported an error

    public init(logLine: String? = nil,
                currentAction: String? = nil,
                finished: Bool = false,
                failed: Bool = false) {
        self.logLine = logLine
        self.currentAction = currentAction
        self.finished = finished
        self.failed = failed
    }
}

public enum StreamJSONParser {
    /// Parse a single NDJSON line into a structured event.
    public static func parseLine(_ line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return .ignored
        }

        switch type {
        case "system":
            return .system(subtype: obj["subtype"] as? String ?? "",
                           sessionId: obj["session_id"] as? String)

        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                return .ignored
            }
            // A single assistant message may carry text and/or a tool_use.
            for block in content {
                let blockType = block["type"] as? String
                if blockType == "tool_use" {
                    let name = block["name"] as? String ?? "tool"
                    let summary = summarize(input: block["input"])
                    return .toolUse(name: shortToolName(name), summary: summary,
                                    rawInput: jsonString(input: block["input"]))
                }
            }
            for block in content where block["type"] as? String == "text" {
                if let text = block["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let question = detectNeedInput(clean) {
                        return .needInput(question: question)
                    }
                    return .assistantText(clean)
                }
            }
            return .ignored

        case "user":
            // tool_result blocks come back as user messages.
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "tool_result" {
                    return .toolResult("tool result")
                }
            }
            return .ignored

        case "result":
            let subtype = obj["subtype"] as? String ?? ""
            let text = obj["result"] as? String
            return .result(subtype: subtype, text: text,
                           sessionId: obj["session_id"] as? String)

        default:
            return .ignored
        }
    }

    /// If an assistant text contains a `NEED_INPUT: <question>` line, return the
    /// question (the text after the marker). Pure — scans line-by-line so the
    /// marker can appear anywhere in a multi-line message. Returns nil otherwise.
    public static func detectNeedInput(_ text: String) -> String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "^NEED_INPUT:\\s*",
                                         options: [.regularExpression, .caseInsensitive]),
                  range.lowerBound == line.startIndex else { continue }
            let question = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !question.isEmpty { return question }
        }
        return nil
    }

    /// Map a parsed event to a UI update, or nil if it should be dropped.
    public static func update(for event: StreamEvent) -> StreamUpdate? {
        switch event {
        case .system, .ignored, .toolResult:
            return nil
        case .assistantText(let text):
            return StreamUpdate(logLine: text)
        case .needInput(let question):
            return StreamUpdate(logLine: "? \(question)", currentAction: "Needs input")
        case .toolUse(let name, let summary, _):
            let action = summary.isEmpty ? name : "\(name) \(summary)"
            return StreamUpdate(logLine: "→ \(action)", currentAction: action)
        case .result(let subtype, let text, _):
            let failed = subtype != "success"
            let line: String
            if failed {
                line = "Run ended: \(subtype)"
            } else if let text, !text.isEmpty {
                line = text
            } else {
                line = "Done."
            }
            return StreamUpdate(logLine: line,
                                currentAction: failed ? "Failed" : "Finished",
                                finished: true,
                                failed: failed)
        }
    }

    // MARK: - Helpers

    /// Strip the `mcp__server__` prefix from a tool name for display.
    static func shortToolName(_ name: String) -> String {
        if let range = name.range(of: "__", options: .backwards) {
            return String(name[range.upperBound...])
        }
        return name
    }

    /// One-line summary of a tool's input arguments.
    static func summarize(input: Any?) -> String {
        guard let dict = input as? [String: Any], !dict.isEmpty else { return "" }
        let parts = dict.keys.sorted().prefix(3).compactMap { key -> String? in
            let value = dict[key]
            if let s = value as? String { return "\(key)=\(s.prefix(40))" }
            if let n = value as? Int { return "\(key)=\(n)" }
            if let d = value as? Double { return "\(key)=\(d)" }
            return nil
        }
        return parts.joined(separator: " ")
    }

    static func jsonString(input: Any?) -> String {
        if let string = input as? String {
            guard let data = string.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return string }
            return jsonString(input: object)
        }
        let object = input ?? [String: Any]()
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
