import Foundation

public func parseStreamLine(_ line: String, backend: AgentBackend) -> StreamEvent {
    switch backend {
    case .claude: return StreamJSONParser.parseLine(line)
    case .codex: return CodexStreamParser.parseLine(line)
    }
}

/// Digests one line from `codex exec --json` into the shared stream model.
public enum CodexStreamParser {
    public static func parseLine(_ line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return .ignored
        }

        switch type {
        case "thread.started":
            return .system(subtype: "init", sessionId: object["thread_id"] as? String)

        case "item.started":
            guard let item = object["item"] as? [String: Any],
                  item["type"] as? String == "mcp_tool_call" else {
                return .ignored
            }
            let name = item["tool"] as? String ?? "tool"
            return .toolUse(name: StreamJSONParser.shortToolName(name),
                            summary: StreamJSONParser.summarize(input: item["arguments"]))

        case "item.completed":
            guard let item = object["item"] as? [String: Any],
                  let itemType = item["type"] as? String else {
                return .ignored
            }
            if itemType == "agent_message" {
                guard let text = item["text"] as? String else { return .ignored }
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return .ignored }
                if let question = StreamJSONParser.detectNeedInput(clean) {
                    return .needInput(question: question)
                }
                return .assistantText(clean)
            }
            if itemType == "mcp_tool_call" {
                if let error = eventText(item["error"]) {
                    return .toolResult(error)
                }
                return .toolResult(eventText(item["result"]) ?? "tool result")
            }
            return .ignored

        case "turn.completed":
            return .result(subtype: "success", text: nil, sessionId: nil)

        case "turn.failed", "error":
            return .result(subtype: "error", text: eventText(object["error"])
                ?? object["message"] as? String, sessionId: nil)

        default:
            return .ignored
        }
    }

    private static func eventText(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        guard let object = value as? [String: Any] else { return nil }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        if let content = object["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return nil
    }
}
