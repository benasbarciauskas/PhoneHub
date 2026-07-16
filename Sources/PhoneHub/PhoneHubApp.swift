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
        runner.deviceResolver = { deviceStore.device(matchingRef: $0) }
        let scheduler = SchedulerRunner(
            scheduleStore: schedules,
            presetStore: presets,
            automationStore: automations,
            deviceStore: deviceStore,
            engine: presetEngine,
            automationRunner: runner,
            chatEngine: chat,
            historyStore: history,
            backendProvider: { LLMConfigStore().load().selectedBackend },
            preferKnownStepsProvider: { LLMConfigStore().load().preferKnownSteps }
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
                if store.layout != .companion {
                    Divider().overlay(Theme.border)
                }
                // Keep Stage mounted in Companion so window-frame observers and
                // docking stay alive; collapse width so PhoneHub is sidebar-only.
                Stage(store: store, automationStore: automationStore,
                      automationRunner: automationRunner, presetEngine: engine,
                      chatEngine: chatEngine, agentBackend: agentBackendBinding.wrappedValue,
                      preferKnownSteps: llmSettings.preferKnownSteps)
                    .frame(minWidth: store.layout == .companion ? 0 : 200)
                    .frame(maxWidth: store.layout == .companion ? 0 : .infinity)
                    .opacity(store.layout == .companion ? 0 : 1)
                    .allowsHitTesting(store.layout != .companion)
            }
            .frame(minWidth: store.layout == .companion ? StageLayout.companionSidebarWidth : 980,
                   minHeight: 720)
            .frame(maxWidth: store.layout == .companion ? StageLayout.companionSidebarWidth : .infinity)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .onAppear {
                store.refresh()
                schedulerRunner.start()
            }
            .onChange(of: store.layout) { previous, layout in
                applyWindowSize(for: layout, previous: previous)
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

    /// Shrink to sidebar width in Companion; restore a usable width when leaving.
    private func applyWindowSize(for layout: StageLayout, previous: StageLayout) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.keyWindow else {
            return
        }
        var frame = window.frame
        if layout == .companion {
            let width = StageLayout.companionSidebarWidth
            // Keep the left edge fixed so the mirror attachment point is stable.
            frame.size.width = width
            window.setFrame(frame, display: true, animate: true)
        } else if previous == .companion {
            frame.size.width = max(980, frame.size.width)
            window.setFrame(frame, display: true, animate: true)
        }
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
