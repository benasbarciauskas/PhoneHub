import SwiftUI

@main
struct PhoneHubApp: App {
    @State private var store = DeviceStore()

    var body: some Scene {
        WindowGroup("PhoneHub") {
            HStack(spacing: 0) {
                Sidebar(store: store)
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
