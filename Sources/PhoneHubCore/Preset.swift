import Foundation

/// A named, AI-driven automation goal. Running it spawns a headless agent
/// wired to the right phone-control MCP for the focused device's platform.
public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var goal: String            // plain-English instruction
    public var app: String?            // optional app to ensure open first
    public var platforms: [Platform]   // [.ios], [.android], or both
    public var maxSteps: Int           // hard cap on agent actions
    public var backend: AgentBackend?  // nil inherits the app default

    public init(id: UUID = UUID(),
                name: String,
                goal: String,
                app: String? = nil,
                platforms: [Platform],
                maxSteps: Int = 40,
                backend: AgentBackend? = nil) {
        self.id = id
        self.name = name
        self.goal = goal
        self.app = app
        self.platforms = platforms
        self.maxSteps = maxSteps
        self.backend = backend
    }

    /// Whether this preset can run on the given device's platform.
    public func supports(_ platform: Platform) -> Bool {
        platforms.contains(platform)
    }
}

public extension Preset {
    /// Built-in presets seeded on first run.
    static var builtIns: [Preset] {
        [
            Preset(name: "Open Instagram",
                   goal: "Open the Instagram app and stop once the home feed is visible.",
                   app: "Instagram",
                   platforms: [.ios, .android]),
            Preset(name: "Warm up TikTok",
                   goal: "Open TikTok and scroll through about 5 videos, dwelling 1–5 seconds "
                       + "on each as a human would. Dismiss any popups or interstitials that "
                       + "appear, then stop.",
                   app: "TikTok",
                   platforms: [.ios, .android])
        ]
    }
}
