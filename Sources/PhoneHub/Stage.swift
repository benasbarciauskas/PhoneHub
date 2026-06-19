import AppKit
import SwiftUI
import PhoneHubCore

struct Stage: View {
    @Bindable var store: DeviceStore

    @State private var scrcpyController = ScrcpyController()
    @State private var mirroringController = MirroringController()
    @State private var activeDevice: Device?
    @State private var stageRect: CGRect = .zero
    @State private var placeholder = StagePlaceholder(title: "Select a device",
                                                      detail: "Connected devices appear in the sidebar.")

    var body: some View {
        ZStack {
            Theme.bg
            PlaceholderView(placeholder: placeholder)
        }
        .background(StageRectReader { rect in
            stageRect = rect
            if activeDevice?.id != store.focusedDevice?.id {
                focus(store.focusedDevice)
            }
        })
        .onAppear {
            focus(store.focusedDevice)
        }
        .onChange(of: store.focusedDevice?.id) { _, _ in
            focus(store.focusedDevice)
        }
        .onDisappear {
            stop(device: activeDevice)
        }
        .animation(Theme.focusSpring, value: store.focusedDevice?.id)
    }

    private func focus(_ device: Device?) {
        guard stageRect.width > 0, stageRect.height > 0 else {
            placeholder = StagePlaceholder(title: device.map { "Docking \($0.model)..." } ?? "Select a device",
                                           detail: "Waiting for the PhoneHub stage to be ready.")
            return
        }

        if activeDevice?.id != device?.id {
            stop(device: activeDevice)
        }
        activeDevice = device

        guard let device else {
            placeholder = StagePlaceholder(title: "Select a device",
                                           detail: "Connected devices appear in the sidebar.")
            return
        }

        // iOS readiness is not tracked like Android so iOS devices always pass the dock check.
        guard device.isReady || device.platform == .ios else {
            placeholder = StagePlaceholder(title: "\(device.model) is not ready",
                                           detail: "Current status: \(device.status)")
            return
        }

        placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                       detail: nil)

        switch device.platform {
        case .android:
            launchAndroid(device)
        case .ios:
            dockIOS(device)
        }
    }

    private func launchAndroid(_ device: Device) {
        let process = scrcpyController.launch(serial: device.id, frame: stageRect)
        if process == nil, scrcpyController.lastState == .missingTool {
            placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                           detail: "scrcpy not installed - brew install scrcpy")
        } else if process == nil {
            placeholder = StagePlaceholder(title: "Could not dock \(device.model)",
                                           detail: "scrcpy failed to start.")
        } else {
            placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                           detail: "Mirror window launched into the stage rectangle.")
        }
    }

    private func dockIOS(_ device: Device) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                           detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility")
            return
        }

        do {
            try mirroringController.dock(into: stageRect)
            placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                           detail: "iPhone Mirroring is positioned in the stage rectangle.")
        } catch {
            placeholder = StagePlaceholder(title: "Could not dock \(device.model)",
                                           detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func stop(device: Device?) {
        guard let device else { return }
        switch device.platform {
        case .android:
            scrcpyController.stop(serial: device.id)
        case .ios:
            mirroringController.stop()
        }
    }
}

private struct StagePlaceholder: Equatable {
    let title: String
    let detail: String?
}

private struct PlaceholderView: View {
    let placeholder: StagePlaceholder

    var body: some View {
        VStack(spacing: Theme.s2) {
            Text(placeholder.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let detail = placeholder.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(Theme.s6)
        .frame(maxWidth: 520)
    }
}

private struct StageRectReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(onChange: onChange)
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class ReportingView: NSView {
        var onChange: (CGRect) -> Void

        init(onChange: @escaping (CGRect) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window else { return }
            let rectInWindow = convert(bounds, to: nil)
            let screenRect = window.convertToScreen(rectInWindow)
            let axRect = screenRect.convertedToAXCoordinates()
            DispatchQueue.main.async {
                self.onChange(axRect)
            }
        }
    }
}

private extension CGRect {
    func convertedToAXCoordinates() -> CGRect {
        guard let primary = NSScreen.screens.first else { return self }
        return CGRect(x: minX,
                      y: primary.frame.height - maxY,
                      width: width,
                      height: height)
    }
}
