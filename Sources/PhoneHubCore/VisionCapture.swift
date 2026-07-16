import Foundation

/// Helpers for API-provider vision: turn MCP screenshot / describe_screen
/// results into a multimodal user message (image + Set-of-Mark text).
/// Does not render numbered overlays onto the image.
public enum VisionCapture {
    /// Build "On-screen elements: [1] Settings (209,100) …" from describe_screen text.
    public static func formatElementList(_ describeText: String) -> String {
        let elements = parseScreenElements(describeText)
        if elements.isEmpty {
            let trimmed = describeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "On-screen elements: (none detected)" }
            return "On-screen elements:\n\(trimmed)"
        }
        let parts = elements.enumerated().map { index, element in
            let x = element.x.rounded() == element.x
                ? String(Int(element.x)) : String(element.x)
            let y = element.y.rounded() == element.y
                ? String(Int(element.y)) : String(element.y)
            return "[\(index + 1)] \(element.label) (\(x),\(y))"
        }
        return "On-screen elements: " + parts.joined(separator: " ")
    }

    /// Resolve image bytes from an MCP screenshot result (inline base64 or file path).
    public static func imageContent(from result: McpToolResult,
                                    fileData: (String) -> Data? = { path in
                                        try? Data(contentsOf: URL(fileURLWithPath: path))
                                    }) -> LLMImageContent? {
        if let base64 = result.imageBase64, !base64.isEmpty {
            return LLMImageContent(
                mediaType: result.imageMediaType ?? "image/png",
                base64: base64
            )
        }
        guard let path = filePath(in: result.text) else { return nil }
        guard let data = fileData(path), !data.isEmpty else { return nil }
        return LLMImageContent(mediaType: mediaType(forPath: path),
                               base64: data.base64EncodedString())
    }

    /// Short summary for stream logs — never include image bytes.
    public static func screenshotLogSummary(for result: McpToolResult) -> String {
        if result.isError {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Screenshot failed." : text
        }
        if result.imageBase64 != nil { return "[image captured]" }
        if let path = filePath(in: result.text) { return "[image path: \(path)]" }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "[screenshot]" : text
    }

    public static func userMessage(image: LLMImageContent?,
                                   describeText: String) -> LLMMessage {
        let text = formatElementList(describeText)
        return LLMMessage(role: .user, content: text, image: image)
    }

    // MARK: - private

    private static func filePath(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isImagePath(trimmed) { return trimmed }
        // JSON-ish: {"path":"/tmp/x.png"} or bare key forms
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["path", "file", "filepath", "file_path", "image_path", "screenshot"] {
                if let value = object[key] as? String, isImagePath(value) { return value }
            }
        }
        // First path-like token on a line
        for line in trimmed.split(whereSeparator: \Character.isNewline) {
            let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if isImagePath(candidate) { return candidate }
            if let match = candidate.range(of: #"(/[^\s\"']+\.(?:png|jpe?g))"#,
                                           options: .regularExpression) {
                return String(candidate[match])
            }
        }
        return nil
    }

    private static func isImagePath(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
        else { return false }
        return value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("~/")
    }

    private static func mediaType(forPath path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        return "image/png"
    }
}
