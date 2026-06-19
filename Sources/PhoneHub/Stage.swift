import AppKit
import Observation
import SwiftUI
import PhoneHubCore

struct Stage: View {
    @Bindable var store: DeviceStore

    @State private var scrcpyController = ScrcpyController()
    @State private var mirroringController = MirroringController()
    @State private var stageState = StageState()
    @State private var dockingTask: Task<Void, Never>?
    @State private var redockTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.bg
            PlaceholderView(placeholder: stageState.placeholder)
        }
        .background(StageRectReader { rect in
            stageState.stageRect = rect
            if stageState.activeDevice?.id != store.focusedDevice?.id {
                focus(store.focusedDevice)
            }
        } onWindowFrameChange: {
            scheduleDockSync()
        })
        .onAppear {
            focus(store.focusedDevice)
        }
        .onChange(of: store.focusedDevice?.id) { _, _ in
            focus(store.focusedDevice)
        }
        .onDisappear {
            dockingTask?.cancel()
            redockTask?.cancel()
            stop(device: stageState.activeDevice)
        }
        .animation(Theme.focusSpring, value: store.focusedDevice?.id)
    }

    private func focus(_ device: Device?) {
        dockingTask?.cancel()
        redockTask?.cancel()
        stageState.isDocked = false

        guard stageState.stageRect.width > 0, stageState.stageRect.height > 0 else {
            stageState.placeholder = StagePlaceholder(title: device.map { "Docking \($0.model)..." } ?? "Select a device",
                                                      detail: "Waiting for the PhoneHub stage to be ready.")
            return
        }

        if stageState.activeDevice?.id != device?.id {
            stop(device: stageState.activeDevice)
        }
        stageState.activeDevice = device

        guard let device else {
            stageState.placeholder = StagePlaceholder(title: "Select a device",
                                                      detail: "Connected devices appear in the sidebar.")
            return
        }

        // iOS readiness is not tracked like Android so iOS devices always pass the dock check.
        guard device.isReady || device.platform == .ios else {
            stageState.placeholder = StagePlaceholder(title: "\(device.model) is not ready",
                                                      detail: "Current status: \(device.status)")
            return
        }

        stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                  detail: nil)

        switch device.platform {
        case .android:
            launchAndroid(device)
        case .ios:
            dockIOS(device)
        }
    }

    private func launchAndroid(_ device: Device) {
        let process = scrcpyController.launch(serial: device.id, frame: stageState.stageRect)
        if process == nil, scrcpyController.lastState == .missingTool {
            stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                      detail: "scrcpy not installed - brew install scrcpy")
        } else if process == nil {
            stageState.placeholder = StagePlaceholder(title: "Could not dock \(device.model)",
                                                      detail: "scrcpy failed to start.")
        } else {
            stageState.isDocked = true
            stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                      detail: "Mirror window launched into the stage rectangle.")
        }
    }

    private func dockIOS(_ device: Device) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                      detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility")
            return
        }

        dockingTask = Task {
            do {
                try await mirroringController.dock(into: stageState.stageRect)
                guard !Task.isCancelled, stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = true
                stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                          detail: "iPhone Mirroring is positioned in the stage rectangle.")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = false
                stageState.placeholder = StagePlaceholder(title: "Could not dock \(device.model)",
                                                          detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func scheduleDockSync() {
        redockTask?.cancel()
        redockTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            resyncDockedWindow()
        }
    }

    private func resyncDockedWindow() {
        guard stageState.isDocked,
              let device = stageState.activeDevice,
              stageState.activeDevice?.id == store.focusedDevice?.id,
              stageState.stageRect.width > 0,
              stageState.stageRect.height > 0 else {
            return
        }

        do {
            switch device.platform {
            case .ios:
                try dockWindow(ownerName: "com.apple.ScreenContinuity", into: stageState.stageRect)
                stageState.placeholder = StagePlaceholder(title: "Docking \(device.model)...",
                                                          detail: "iPhone Mirroring is positioned in the stage rectangle.")
            case .android:
                // Android is launched with an initial scrcpy frame; WindowDock currently targets apps,
                // not a scrcpy window title, so live AX re-positioning is left unchanged.
                break
            }
        } catch {
            stageState.isDocked = false
            stageState.placeholder = StagePlaceholder(title: "Could not dock \(device.model)",
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

@Observable
@MainActor
private final class StageState {
    var activeDevice: Device?
    var stageRect: CGRect = .zero
    var isDocked = false
    var placeholder = StagePlaceholder(title: "Select a device",
                                       detail: "Connected devices appear in the sidebar.")
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
    let onWindowFrameChange: () -> Void

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(onChange: onChange, onWindowFrameChange: onWindowFrameChange)
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.onWindowFrameChange = onWindowFrameChange
        nsView.report()
    }

    final class ReportingView: NSView {
        var onChange: (CGRect) -> Void
        var onWindowFrameChange: () -> Void
        private weak var observedWindow: NSWindow?
        private var observerTokens: [NSObjectProtocol] = []

        init(onChange: @escaping (CGRect) -> Void, onWindowFrameChange: @escaping () -> Void) {
            self.onChange = onChange
            self.onWindowFrameChange = onWindowFrameChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            removeWindowObservers()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installWindowObserversIfNeeded()
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

        private func installWindowObserversIfNeeded() {
            guard observedWindow !== window else { return }
            removeWindowObservers()
            guard let window else { return }
            observedWindow = window

            let center = NotificationCenter.default
            let notifications: [NSNotification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification
            ]
            observerTokens = notifications.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.report()
                    self?.onWindowFrameChange()
                }
            }
        }

        private func removeWindowObservers() {
            let center = NotificationCenter.default
            observerTokens.forEach { center.removeObserver($0) }
            observerTokens.removeAll()
            observedWindow = nil
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
