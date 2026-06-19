import SwiftUI
import PhoneHubCore
import UniformTypeIdentifiers

struct Stage: View {
    @Bindable var store: DeviceStore

    var body: some View {
        ZStack {
            Theme.bg
            if let device = store.focused, device.isReady {
                VStack(spacing: Theme.s3) {
                    HStack {
                        Text(device.model).font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Button { saveScreenshot(device.id) } label: {
                            Label("Screenshot", systemImage: "camera")
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    StreamView(serial: device.id)
                        .id(device.id)
                        .cardSurface()
                }
                .padding(Theme.s6)
                .transition(.opacity)
            } else {
                Text(store.focused == nil ? "Select a device" : "Device not ready")
                    .foregroundStyle(Theme.subtext)
            }
        }
        .animation(Theme.focusSpring, value: store.focusedID)
    }

    private func saveScreenshot(_ serial: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(serial)-\(Int(Date().timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached { AndroidController.saveScreenshot(serial: serial, to: url) }
        }
    }
}
