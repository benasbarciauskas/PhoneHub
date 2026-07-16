import AppKit
import SwiftUI
import PhoneHubCore

@main
struct PhoneHubApp: App {
    @State private var store: DeviceStore
    @State private var presetStore: PresetStore
    @State private var automationStore: AutomationStore
    @State private var historyStore: RunHistoryStore
    @State private var scheduleStore: ScheduleStore
    @State private var engine: AutomationEngine
    @State private var chatEngine: ChatEngine
    @State private var automationRunner: AutomationRunner
    @State private var schedulerRunner: SchedulerRunner
    @State private var llmSettings: LLMSettingsModel
    @State private var mirrorRaiseTask: Task<Void, Never>?

    private var agentBackendBinding: Binding<AgentBackend> {
        Binding(
            get: { llmSettings.selectedBackend },
            set: { llmSettings.selectBackend($0) }
        )
    }

    init() {
        let deviceStore = DeviceStore()
        let presets = PresetStore()
        let automations = AutomationStore()
        let history = RunHistoryStore()
        let schedules = ScheduleStore()
        let presetEngine = AutomationEngine()
        let chat = ChatEngine()
        presetEngine.runHistoryStore = history
        let runner = AutomationRunner(store: automations, agentEngine: presetEngine)
        runner.runHistoryStore = history
        let scheduler = SchedulerRunner(
            scheduleStore: schedules,
            presetStore: presets,
            automationStore: automations,
            deviceStore: deviceStore,
            engine: presetEngine,
            automationRunner: runner,
            chatEngine: chat,
            historyStore: history,
            backendProvider: { LLMConfigStore().load().selectedBackend }
        )

        _store = State(initialValue: deviceStore)
        _presetStore = State(initialValue: presets)
        _automationStore = State(initialValue: automations)
        _historyStore = State(initialValue: history)
        _scheduleStore = State(initialValue: schedules)
        _engine = State(initialValue: presetEngine)
        _chatEngine = State(initialValue: chat)
        _llmSettings = State(initialValue: LLMSettingsModel())
        _automationRunner = State(initialValue: runner)
        _schedulerRunner = State(initialValue: scheduler)
    }

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store, presetStore: presetStore, automationStore: automationStore,
                        historyStore: historyStore, scheduleStore: scheduleStore,
                        engine: engine, chatEngine: chatEngine, automationRunner: automationRunner,
                        agentBackend: agentBackendBinding, llmSettings: llmSettings)
                Divider().overlay(Theme.border)
                Stage(store: store, automationStore: automationStore,
                      automationRunner: automationRunner, presetEngine: engine,
                      chatEngine: chatEngine, agentBackend: agentBackendBinding.wrappedValue)
            }
            .frame(minWidth: 980, minHeight: 720)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .onAppear {
                store.refresh()
                schedulerRunner.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                scheduleDockedMirrorRaise()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                scheduleDockedMirrorRaise()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { _ in
                scheduleDockedMirrorRaise()
            }
            .onDisappear {
                mirrorRaiseTask?.cancel()
                schedulerRunner.stop()
                chatEngine.shutdown()
            }
        }
        .windowStyle(.hiddenTitleBar)
    }

    private func scheduleDockedMirrorRaise() {
        mirrorRaiseTask?.cancel()
        mirrorRaiseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            raiseDockedIPhoneMirroringWindows()
        }
    }
}
