import SwiftUI
import PhoneHubCore

@main
struct PhoneHubApp: App {
    @State private var store: DeviceStore
    @State private var presetStore: PresetStore
    @State private var automationStore: AutomationStore
    @State private var engine: AutomationEngine
    @State private var chatEngine: ChatEngine
    @State private var automationRunner: AutomationRunner
    @AppStorage("agentBackend") private var agentBackendRawValue = AgentBackend.claude.rawValue

    private var agentBackendBinding: Binding<AgentBackend> {
        Binding(
            get: { AgentBackend(rawValue: agentBackendRawValue) ?? .claude },
            set: { agentBackendRawValue = $0.rawValue }
        )
    }

    init() {
        let deviceStore = DeviceStore()
        let presets = PresetStore()
        let automations = AutomationStore()
        let presetEngine = AutomationEngine()
        let chat = ChatEngine()
        _store = State(initialValue: deviceStore)
        _presetStore = State(initialValue: presets)
        _automationStore = State(initialValue: automations)
        _engine = State(initialValue: presetEngine)
        _chatEngine = State(initialValue: chat)
        _automationRunner = State(initialValue: AutomationRunner(store: automations,
                                                                 agentEngine: presetEngine))
    }

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store, presetStore: presetStore, automationStore: automationStore,
                        engine: engine, chatEngine: chatEngine, automationRunner: automationRunner,
                        agentBackend: agentBackendBinding)
                Divider().overlay(Theme.border)
                Stage(store: store, automationStore: automationStore,
                      automationRunner: automationRunner, presetEngine: engine,
                      chatEngine: chatEngine, agentBackend: agentBackendBinding.wrappedValue)
            }
            .frame(minWidth: 980, minHeight: 720)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .onAppear { store.refresh() }
            .onDisappear { chatEngine.shutdown() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
