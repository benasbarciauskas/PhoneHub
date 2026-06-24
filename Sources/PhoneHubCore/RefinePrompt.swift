import Foundation

/// Pure builders for the AI "refine" feature: rewrite a user's rough text into a
/// single clear, concrete phone-automation instruction. No I/O here so the prompt
/// is unit-testable; the engine shells `claude -p` with these (text-only, NO tools,
/// NO --mcp-config).
public enum RefinePrompt {
    /// The instruction half of the refine prompt (what we ask the model to do).
    public static let instruction = """
    Rewrite this into a single clear, concrete instruction for an agent operating \
    a phone. Keep the user's intent. Output only the rewritten instruction.
    """

    /// The full `-p` prompt: instruction followed by the raw user text.
    public static func prompt(for text: String) -> String {
        "\(instruction)\n\n\(text)"
    }

    /// argv for the text-only refine spawn. No tools, no mcp-config — just a
    /// rewrite. `--output-format text` so we read the rewritten goal verbatim.
    public static func arguments(for text: String) -> [String] {
        ["-p", prompt(for: text), "--output-format", "text"]
    }
}
