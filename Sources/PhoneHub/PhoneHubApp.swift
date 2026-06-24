import SwiftUI
import PhoneHubCore

@main
struct PhoneHubApp: App {
    @State private var store = DeviceStore()
    @State private var presetStore = PresetStore()
    @State private var engine = AutomationEngine()

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store, presetStore: presetStore, engine: engine)
                Divider().overlay(Theme.border)
                Stage(store: store)
            }
            .frame(minWidth: 980, minHeight: 720)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .onAppear { store.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
