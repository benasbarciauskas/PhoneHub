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
    @State private var stageWindow: NSWindow?

    private let mirrorInset: CGFloat = 12
    private let wallInset: CGFloat = 16
    private let wallSpacing: CGFloat = 12
    private let sidebarWidth: CGFloat = 240

    var body: some View {
        ZStack {
            Theme.bg
            if store.layout == .wall {
                WallGridView(devices: wallDevices,
                             placeholders: stageState.wallPlaceholders,
                             inset: wallInset,
                             spacing: wallSpacing)
            } else {
                PlaceholderView(placeholder: stageState.placeholder)
            }
        }
        .background(StageRectReader { rect in
            stageState.stageRect = rect
            if store.layout == .wall {
                scheduleDockSync()
            } else if stageState.activeDevice?.id != store.focusedDevice?.id {
                focus(store.focusedDevice)
            }
        } onWindowFrameChange: {
            scheduleDockSync()
        } onWindowAvailable: { window in
            stageWindow = window
        })
        .onAppear {
            syncLayout()
        }
        .onChange(of: store.focusedDevice?.id) { _, _ in
            syncLayout()
        }
        .onChange(of: store.layout) { _, _ in
            syncLayout()
        }
        .onChange(of: store.devices) { _, _ in
            if store.layout == .wall {
                syncLayout()
            }
        }
        .onDisappear {
            dockingTask?.cancel()
            redockTask?.cancel()
            stopWall()
            stop(device: stageState.activeDevice)
        }
        .animation(Theme.focusSpring, value: store.focusedDevice?.id)
        .animation(Theme.focusSpring, value: store.layout)
    }

    private var wallDevices: [Device] {
        Array(store.devices.filter { device in
            switch device.platform {
            case .android:
                return device.isReady
            case .ios:
                return device.status == "connected"
            }
        }.prefix(9))
    }

    private func syncLayout() {
        switch store.layout {
        case .focus:
            stopWall()
            focus(store.focusedDevice)
        case .wall:
            if let activeDevice = stageState.activeDevice {
                stop(device: activeDevice)
            }
            stageState.activeDevice = nil
            stageState.isDocked = false
            syncWall()
        }
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

        if let placeholder = stageNotConnectedIOSPlaceholder(for: device) {
            stageState.placeholder = placeholder
            return
        }

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
                let mirrorSize = try dockWindow(ownerName: "com.apple.ScreenContinuity", into: stageState.stageRect)
                guard !Task.isCancelled, stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = true
                if growStageWindowIfNeeded(forMirrorSize: mirrorSize) {
                    scheduleDockSync()
                }
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
            switch store.layout {
            case .focus:
                resyncDockedWindow()
            case .wall:
                syncWall()
            }
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
                let mirrorSize = try dockWindow(ownerName: "com.apple.ScreenContinuity", into: stageState.stageRect)
                if growStageWindowIfNeeded(forMirrorSize: mirrorSize) {
                    scheduleDockSync()
                }
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

    private func syncWall() {
        dockingTask?.cancel()
        guard stageState.stageRect.width > 0, stageState.stageRect.height > 0 else {
            stageState.wallPlaceholders = [:]
            return
        }

        let devices = wallDevices
        let activeIDs = Set(devices.map(\.id))
        let staleAndroidSerials = stageState.wallAndroidSerials.subtracting(activeIDs)
        staleAndroidSerials.forEach { scrcpyController.stop(serial: $0) }
        stageState.wallAndroidSerials.subtract(staleAndroidSerials)
        stageState.wallPlaceholders = stageState.wallPlaceholders.filter { activeIDs.contains($0.key) }
        if devices.isEmpty {
            stageState.wallPlaceholders = ["empty": StagePlaceholder(title: "No ready devices",
                                                                     detail: "Connected devices appear in the sidebar.")]
            return
        }

        let rects = gridTileRects(count: devices.count,
                                  within: stageState.stageRect,
                                  inset: wallInset,
                                  spacing: wallSpacing)
        let liveIOSID = wallLiveIOSDevice(in: devices)?.id
        if liveIOSID == nil, stageState.wallIOSDeviceID != nil {
            mirroringController.stop()
            stageState.wallIOSDeviceID = nil
        }

        for (device, rect) in zip(devices, rects) {
            switch device.platform {
            case .android:
                syncWallAndroid(device, rect: rect)
            case .ios:
                if device.id == liveIOSID {
                    syncWallIOS(device, rect: rect)
                } else {
                    stageState.wallPlaceholders[device.id] = StagePlaceholder(
                        title: device.model,
                        detail: "iPhone Mirroring shows one iPhone at a time"
                    )
                }
            }
        }
    }

    private func wallLiveIOSDevice(in devices: [Device]) -> Device? {
        if let focused = store.focusedDevice,
           focused.platform == .ios,
           let device = devices.first(where: { $0.id == focused.id }) {
            return device
        }

        return devices.first { $0.platform == .ios }
    }

    private func syncWallAndroid(_ device: Device, rect: CGRect) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: device.model,
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
            return
        }

        if !stageState.wallAndroidSerials.contains(device.id) {
            let process = scrcpyController.launch(serial: device.id, frame: rect)
            if process == nil, scrcpyController.lastState == .missingTool {
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: device.model,
                                                                          detail: "scrcpy not installed - brew install scrcpy")
                return
            } else if process == nil {
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: device.model,
                                                                          detail: "scrcpy failed to start.")
                return
            }
            stageState.wallAndroidSerials.insert(device.id)
        }

        do {
            try dockWindow(byTitle: "PhoneHub-\(device.id)", into: rect)
            stageState.wallPlaceholders[device.id] = StagePlaceholder(title: device.model,
                                                                      detail: nil)
        } catch {
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: device.model,
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            if case WindowDockError.windowNotFound = error {
                scheduleDockSync()
            }
        }
    }

    private func syncWallIOS(_ device: Device, rect: CGRect) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: device.model,
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
            return
        }

        stageState.wallPlaceholders[device.id] = StagePlaceholder(title: "Docking \(device.model)...",
                                                                  detail: nil)
        stageState.wallIOSDeviceID = device.id
        dockingTask = Task {
            do {
                try await mirroringController.dock(into: rect)
                guard !Task.isCancelled, store.layout == .wall else { return }
                try dockWindow(ownerName: "com.apple.ScreenContinuity", into: rect)
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: device.model,
                                                                          detail: nil)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.layout == .wall else { return }
                stageState.wallPlaceholders[device.id] = StagePlaceholder(
                    title: device.model,
                    detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    private func stopWall() {
        stageState.wallAndroidSerials.forEach { scrcpyController.stop(serial: $0) }
        if stageState.wallIOSDeviceID != nil {
            mirroringController.stop()
        }
        stageState.wallAndroidSerials.removeAll()
        stageState.wallIOSDeviceID = nil
        stageState.wallPlaceholders.removeAll()
    }

    private func growStageWindowIfNeeded(forMirrorSize mirrorSize: CGSize) -> Bool {
        guard let window = stageWindow,
              let screen = window.screen ?? NSScreen.main else {
            return false
        }

        let requiredStage = requiredStageSize(forMirrorSize: mirrorSize, inset: mirrorInset)
        let requiredWindowSize = CGSize(width: requiredStage.width + sidebarWidth,
                                        height: requiredStage.height)
        let currentFrame = window.frame
        let visibleFrame = screen.visibleFrame

        var targetWidth = max(currentFrame.width, window.minSize.width, requiredWindowSize.width)
        var targetHeight = max(currentFrame.height, window.minSize.height, requiredWindowSize.height)

        targetWidth = min(targetWidth, visibleFrame.width)
        targetHeight = min(targetHeight, visibleFrame.height)

        guard targetWidth > currentFrame.width + 0.5 || targetHeight > currentFrame.height + 0.5 else {
            return false
        }

        let topY = currentFrame.maxY
        var targetFrame = CGRect(x: currentFrame.minX,
                                 y: topY - targetHeight,
                                 width: targetWidth,
                                 height: targetHeight)

        if targetFrame.maxX > visibleFrame.maxX {
            targetFrame.origin.x = visibleFrame.maxX - targetFrame.width
        }
        if targetFrame.minX < visibleFrame.minX {
            targetFrame.origin.x = visibleFrame.minX
        }
        if targetFrame.minY < visibleFrame.minY {
            targetFrame.origin.y = visibleFrame.minY
        }
        if targetFrame.maxY > visibleFrame.maxY {
            targetFrame.origin.y = visibleFrame.maxY - targetFrame.height
        }

        window.setFrame(targetFrame, display: true, animate: false)
        return true
    }
}

struct StagePlaceholder: Equatable {
    let title: String
    let detail: String?
}

func stageNotConnectedIOSPlaceholder(for device: Device) -> StagePlaceholder? {
    guard device.platform == .ios, device.status == "notConnected" else {
        return nil
    }

    return StagePlaceholder(title: "\(device.model) — not connected",
                            detail: "Bring it near + unlock (same Apple ID), or it may be mirrored elsewhere. macOS mirrors one iPhone at a time.")
}

@Observable
@MainActor
private final class StageState {
    var activeDevice: Device?
    var stageRect: CGRect = .zero
    var isDocked = false
    var wallAndroidSerials: Set<String> = []
    var wallIOSDeviceID: String?
    var wallPlaceholders: [String: StagePlaceholder] = [:]
    var placeholder = StagePlaceholder(title: "Select a device",
                                       detail: "Connected devices appear in the sidebar.")
}

private struct WallGridView: View {
    let devices: [Device]
    let placeholders: [String: StagePlaceholder]
    let inset: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let visibleDevices = devices.isEmpty ? [Device(id: "empty",
                                                           platform: .ios,
                                                           model: "No ready devices",
                                                           osVersion: "",
                                                           status: "connected")] : devices
            let rects = gridTileRects(count: visibleDevices.count,
                                      within: CGRect(origin: .zero, size: proxy.size),
                                      inset: inset,
                                      spacing: spacing)
            ForEach(Array(zip(visibleDevices, rects)), id: \.0.id) { device, rect in
                WallTileView(placeholder: placeholders[device.id] ?? StagePlaceholder(title: device.model,
                                                                                       detail: nil))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}

private struct WallTileView: View {
    let placeholder: StagePlaceholder

    var body: some View {
        VStack(spacing: Theme.s2) {
            Text(placeholder.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let detail = placeholder.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: 1))
    }
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
    let onWindowAvailable: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(onChange: onChange,
                      onWindowFrameChange: onWindowFrameChange,
                      onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.onWindowFrameChange = onWindowFrameChange
        nsView.onWindowAvailable = onWindowAvailable
        nsView.report()
    }

    final class ReportingView: NSView {
        var onChange: (CGRect) -> Void
        var onWindowFrameChange: () -> Void
        var onWindowAvailable: (NSWindow?) -> Void
        private weak var observedWindow: NSWindow?
        private var observerTokens: [NSObjectProtocol] = []

        init(onChange: @escaping (CGRect) -> Void,
             onWindowFrameChange: @escaping () -> Void,
             onWindowAvailable: @escaping (NSWindow?) -> Void) {
            self.onChange = onChange
            self.onWindowFrameChange = onWindowFrameChange
            self.onWindowAvailable = onWindowAvailable
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
            onWindowAvailable(window)
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
            onWindowAvailable(window)

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
