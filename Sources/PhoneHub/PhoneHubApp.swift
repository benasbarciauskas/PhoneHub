import SwiftUI
import PhoneHubCore

@main
struct PhoneHubApp: App {
    @State private var store = DeviceStore()
    @State private var presetStore = PresetStore()
    @State private var engine = AutomationEngine()
    @State private var chatEngine = ChatEngine()
    @AppStorage("agentBackend") private var agentBackendRawValue = AgentBackend.claude.rawValue

    private var agentBackendBinding: Binding<AgentBackend> {
        Binding(
            get: { AgentBackend(rawValue: agentBackendRawValue) ?? .claude },
            set: { agentBackendRawValue = $0.rawValue }
        )
    }

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store, presetStore: presetStore,
                        engine: engine, chatEngine: chatEngine,
                        agentBackend: agentBackendBinding)
                Divider().overlay(Theme.border)
                Stage(store: store)
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
