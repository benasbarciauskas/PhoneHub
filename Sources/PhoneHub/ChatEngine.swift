import Foundation
import Observation
import PhoneHubCore

@Observable
@MainActor
final class ChatEngine {
    enum TurnState: Equatable {
        case idle
        case running
        case failed(String)
    }

    private(set) var chat: DeviceChat = .empty
    private(set) var turnState: TurnState = .idle
    private(set) var streamingText = ""

    private let store: ChatStore
    private var process: StreamingProcess?
    private var configURL: URL?
    private var boundDeviceId: String?
    private var currentPlan: AutomationPlan?
    private var executablePath: String?
    private var pendingText = ""
    private var isResumeTurn = false
    private var alreadyRetried = false
    private var resultFailure: String?

    init(store: ChatStore = ChatStore(
        directory: PresetStore.defaultDirectory().appendingPathComponent("chats", isDirectory: true)
    )) {
        self.store = store
    }

    var isBusy: Bool {
        turnState == .running
    }

    func bind(device: Device) {
        guard boundDeviceId != device.id else { return }
        if isBusy { stop() }
        cleanupConfig()
        boundDeviceId = device.id
        chat = store.load(deviceId: device.id)
        turnState = .idle
        streamingText = ""
    }

    func send(_ text: String, on device: Device, presetEngineBusy: Bool) {
        guard !isBusy else { return }
        bind(device: device)
        if presetEngineBusy {
            append(.system, "A preset run is active — wait or stop it.")
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let status = BackendAvailability.check(chat.backend)
        guard case let .available(path) = status else {
            if case let .missing(hint) = status { append(.system, hint) }
            return
        }

        let plan: AutomationPlan
        do {
            plan = try buildChatPlan(device: device, backend: chat.backend)
        } catch {
            fail("Could not prepare chat: \(error)")
            return
        }

        append(.user, trimmed)
        currentPlan = plan
        executablePath = path
        pendingText = trimmed
        alreadyRetried = false
        resultFailure = nil
        start(plan: plan, asResume: chat.sessionId != nil)
    }

    func stop() {
        guard isBusy else { return }
        process?.stop()
        process = nil
        flushStreaming(suffix: " — (stopped)")
        turnState = .idle
        persist()
    }

    func newChat(deviceId: String) {
        if isBusy { stop() }
        cleanupConfig()
        let backend = chat.backend
        chat = DeviceChat(messages: [], sessionId: nil, backend: backend)
        boundDeviceId = deviceId
        turnState = .idle
        streamingText = ""
        persist()
    }

    func shutdown() {
        process?.stop()
        process = nil
        cleanupConfig()
    }

    private func start(plan: AutomationPlan, asResume: Bool) {
        guard let executablePath else { return }
        if configURL == nil {
            guard let url = writeConfig(plan.mcpConfigJSON) else { return }
            configURL = url
        }
        guard let configURL else { return }

        var launchPlan = plan
        launchPlan.prompt = pendingText
        let args: [String]
        if asResume, let sessionId = chat.sessionId {
            args = launchPlan.resumeArguments(
                sessionId: sessionId,
                reply: pendingText,
                mcpConfigPath: configURL.path
            )
        } else {
            args = launchPlan.arguments(mcpConfigPath: configURL.path)
        }

        isResumeTurn = asResume
        streamingText = ""
        resultFailure = nil
        turnState = .running
        spawn(executablePath: executablePath, args: args)
    }

    private func spawn(executablePath: String, args: [String]) {
        let proc = StreamingProcess(executablePath: executablePath, arguments: args)
        process = proc
        do {
            try proc.start(
                onLine: { [weak self] line in
                    Task { @MainActor in self?.handle(line: line) }
                },
                onExit: { [weak self] code, reason in
                    Task { @MainActor in self?.handleExit(code: code, reason: reason) }
                }
            )
        } catch {
            process = nil
            fail("Failed to launch \(chat.backend.rawValue): \(error)")
        }
    }

    private func handle(line: String) {
        let event = StreamJSONParser.parseLine(line)
        if case let .system(_, sessionId) = event, let sessionId, !sessionId.isEmpty {
            chat.sessionId = sessionId
            persist()
        }
        if case let .result(_, _, sessionId) = event, let sessionId, !sessionId.isEmpty {
            chat.sessionId = sessionId
            persist()
        }
        switch event {
        case .system:
            break
        case let .assistantText(text):
            if !streamingText.isEmpty { streamingText += "\n" }
            streamingText += text
        case let .toolUse(name, _):
            append(.tool, "▸ \(name)")
        case let .result(subtype, text, _):
            if streamingText.isEmpty, let text, !text.isEmpty { streamingText = text }
            if subtype != "success" { resultFailure = text ?? subtype }
        case let .needInput(question):
            if !streamingText.isEmpty { streamingText += "\n" }
            streamingText += question
        case .toolResult, .ignored:
            break
        }
    }

    private func handleExit(code: Int32, reason: String) {
        process = nil
        guard isBusy else { return }

        if ChatTurn.shouldRetryAsFresh(
            exitCode: code,
            isResumeTurn: isResumeTurn,
            alreadyRetried: alreadyRetried
        ) {
            alreadyRetried = true
            chat.sessionId = nil
            persist()
            cleanupConfig()
            if let plan = currentPlan {
                start(plan: plan, asResume: false)
                return
            }
        }

        flushStreaming()
        if code == 0, resultFailure == nil {
            turnState = .idle
        } else {
            let message = resultFailure
                ?? (reason.isEmpty ? "\(chat.backend.rawValue) exited with code \(code)" : reason)
            append(.system, message)
            turnState = .failed(message)
        }
        persist()
    }

    private func append(_ role: ChatMessage.Role, _ text: String) {
        chat.messages.append(ChatMessage(role: role, text: text))
        persist()
    }

    private func flushStreaming(suffix: String = "") {
        guard !streamingText.isEmpty else { return }
        chat.messages.append(ChatMessage(role: .assistant, text: streamingText + suffix))
        streamingText = ""
        persist()
    }

    private func fail(_ message: String) {
        append(.system, message)
        turnState = .failed(message)
    }

    private func persist() {
        guard let boundDeviceId else { return }
        store.save(chat, deviceId: boundDeviceId)
    }

    private func writeConfig(_ json: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-chat-mcp-\(UUID().uuidString).json")
        do {
            try json.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            fail("Could not write MCP config: \(error)")
            return nil
        }
    }

    private func cleanupConfig() {
        if let configURL { try? FileManager.default.removeItem(at: configURL) }
        configURL = nil
    }
}
