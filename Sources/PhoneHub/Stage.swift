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
    @State private var dockingTaskDeviceID: String?
    @State private var dockingTaskID: UUID?
    @State private var dockingTaskIsWall = false
    @State private var redockTask: Task<Void, Never>?
    @State private var isSyncingDock = false

    private let wallInset: CGFloat = 16
    private let wallSpacing: CGFloat = 12

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

            if shouldShowMirroringRail {
                MirroringNavigationRail { itemName in
                    Task { @MainActor in
                        guard let pid = findIPhoneMirroringApp()?.processIdentifier else { return }
                        _ = pressViewMenuItem(pid: pid, named: itemName)
                    }
                }
                .padding(.bottom, Theme.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
        })
        .onAppear {
            syncLayout()
        }
        .onChange(of: store.focusedDevice?.id) { _, _ in
            syncLayout()
        }
        .onChange(of: store.layout) { _, _ in
            stageState.menuFittedIOSDeviceIDs.removeAll()
            syncLayout()
        }
        .onChange(of: store.devices) { _, _ in
            if store.layout == .wall {
                syncLayout()
            }
        }
        .onDisappear {
            cancelDockingTask()
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

    private var shouldShowMirroringRail: Bool {
        guard store.layout == .focus,
              stageState.isDocked,
              let device = stageState.activeDevice,
              device.id == store.focusedDevice?.id,
              device.platform == .ios,
              device.status == "connected" else {
            return false
        }
        return true
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
        cancelDockingTask()
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

        let taskID = UUID()
        dockingTaskDeviceID = device.id
        dockingTaskID = taskID
        dockingTaskIsWall = false
        dockingTask = Task {
            defer {
                if dockingTaskID == taskID {
                    dockingTask = nil
                    dockingTaskDeviceID = nil
                    dockingTaskID = nil
                    dockingTaskIsWall = false
                }
            }
            do {
                if stageState.menuFittedIOSDeviceIDs.contains(device.id) {
                    try dockWindow(ownerName: "com.apple.ScreenContinuity",
                                   into: stageState.stageRect,
                                   activate: false)
                } else {
                    // This initial dock may open the View menu once to fit iPhone Mirroring.
                    try await mirroringController.dock(into: stageState.stageRect)
                    stageState.menuFittedIOSDeviceIDs.insert(device.id)
                }
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
            guard !Task.isCancelled, !isSyncingDock else { return }
            isSyncingDock = true
            defer { isSyncingDock = false }
            switch store.layout {
            case .focus:
                await resyncDockedWindow()
            case .wall:
                syncWall()
            }
        }
    }

    private func resyncDockedWindow() async {
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
                // Reposition ONLY — never call the menu-fit (fitMirrorToRect) here; doing so on every layout-driven resync caused a runaway loop that opened iPhone Mirroring's View menu continuously and locked up the Mac. Menu-fit runs once per dock, guarded by menuFittedIOSDeviceIDs.
                try dockWindow(ownerName: "com.apple.ScreenContinuity",
                               into: stageState.stageRect,
                               activate: false)
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
            stageState.menuFittedIOSDeviceIDs.remove(device.id)
        }
    }

    private func syncWall() {
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
        if liveIOSID == nil {
            if stageState.wallIOSDeviceID != nil || (dockingTaskIsWall && dockingTaskDeviceID != nil) {
                cancelDockingTask()
                mirroringController.stop()
                if let wallIOSDeviceID = stageState.wallIOSDeviceID {
                    stageState.menuFittedIOSDeviceIDs.remove(wallIOSDeviceID)
                }
                stageState.wallIOSDeviceID = nil
            }
        } else if stageState.wallIOSDeviceID != nil, stageState.wallIOSDeviceID != liveIOSID {
            cancelDockingTask()
            mirroringController.stop()
            if let wallIOSDeviceID = stageState.wallIOSDeviceID {
                stageState.menuFittedIOSDeviceIDs.remove(wallIOSDeviceID)
            }
            stageState.wallIOSDeviceID = nil
        } else if dockingTaskDeviceID != nil,
                  (!dockingTaskIsWall || dockingTaskDeviceID != liveIOSID) {
            cancelDockingTask()
        }

        var didRequestAccessibility = false
        for (device, rect) in zip(devices, rects) {
            switch device.platform {
            case .android:
                syncWallAndroid(device, rect: rect, didRequestAccessibility: &didRequestAccessibility)
            case .ios:
                if device.id == liveIOSID {
                    syncWallIOS(device, rect: rect, didRequestAccessibility: &didRequestAccessibility)
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

    private func syncWallAndroid(_ device: Device, rect: CGRect, didRequestAccessibility: inout Bool) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityPromptIfNeeded(didRequestAccessibility: &didRequestAccessibility)
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
            guard let processIdentifier = scrcpyController.processIdentifier(for: device.id) else {
                throw WindowDockError.windowNotFound("PhoneHub-\(device.id)")
            }
            try dockWindow(byTitle: "PhoneHub-\(device.id)", processIdentifier: processIdentifier, into: rect)
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

    private func syncWallIOS(_ device: Device, rect: CGRect, didRequestAccessibility: inout Bool) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityPromptIfNeeded(didRequestAccessibility: &didRequestAccessibility)
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: device.model,
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
            return
        }

        if dockingTaskIsWall, dockingTaskDeviceID == device.id {
            stageState.wallPlaceholders[device.id] = StagePlaceholder(title: "Docking \(device.model)...",
                                                                      detail: nil)
            return
        }

        if stageState.wallIOSDeviceID == device.id {
            dockWallIOS(device, rect: rect)
            return
        }

        cancelDockingTask()
        stageState.wallPlaceholders[device.id] = StagePlaceholder(title: "Docking \(device.model)...",
                                                                  detail: nil)
        let taskID = UUID()
        dockingTaskDeviceID = device.id
        dockingTaskID = taskID
        dockingTaskIsWall = true
        dockingTask = Task {
            defer {
                if dockingTaskID == taskID {
                    dockingTask = nil
                    dockingTaskDeviceID = nil
                    dockingTaskID = nil
                    dockingTaskIsWall = false
                }
            }
            do {
                if stageState.menuFittedIOSDeviceIDs.contains(device.id) {
                    try dockWindow(ownerName: "com.apple.ScreenContinuity",
                                   into: rect,
                                   activate: false)
                } else {
                    // This initial wall dock may open the View menu once to fit iPhone Mirroring.
                    try await mirroringController.dock(into: rect)
                    stageState.menuFittedIOSDeviceIDs.insert(device.id)
                }
                guard !Task.isCancelled, store.layout == .wall else { return }
                stageState.wallIOSDeviceID = device.id
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

    private func dockWallIOS(_ device: Device, rect: CGRect) {
        cancelDockingTask()
        stageState.wallPlaceholders[device.id] = StagePlaceholder(title: device.model,
                                                                  detail: nil)
        let taskID = UUID()
        dockingTaskDeviceID = device.id
        dockingTaskID = taskID
        dockingTaskIsWall = true
        dockingTask = Task {
            defer {
                if dockingTaskID == taskID {
                    dockingTask = nil
                    dockingTaskDeviceID = nil
                    dockingTaskID = nil
                    dockingTaskIsWall = false
                }
            }
            do {
                // Reposition ONLY — never call the menu-fit (fitMirrorToRect) here; doing so on every layout-driven resync caused a runaway loop that opened iPhone Mirroring's View menu continuously and locked up the Mac. Menu-fit runs once per dock, guarded by menuFittedIOSDeviceIDs.
                try dockWindow(ownerName: "com.apple.ScreenContinuity",
                               into: rect,
                               activate: false)
                guard !Task.isCancelled, store.layout == .wall else { return }
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
                stageState.wallIOSDeviceID = nil
                scheduleDockSync()
            }
        }
    }

    private func stopWall() {
        stageState.wallAndroidSerials.forEach { scrcpyController.stop(serial: $0) }
        scrcpyController.stopAll()
        if stageState.wallIOSDeviceID != nil || (dockingTaskIsWall && dockingTaskDeviceID != nil) {
            cancelDockingTask()
            mirroringController.stop()
        }
        stageState.wallAndroidSerials.removeAll()
        stageState.wallIOSDeviceID = nil
        stageState.wallPlaceholders.removeAll()
        stageState.menuFittedIOSDeviceIDs.removeAll()
    }

    private func cancelDockingTask() {
        dockingTask?.cancel()
        dockingTask = nil
        dockingTaskDeviceID = nil
        dockingTaskID = nil
        dockingTaskIsWall = false
    }

    private func requestAccessibilityPromptIfNeeded(didRequestAccessibility: inout Bool) {
        guard !didRequestAccessibility else { return }
        didRequestAccessibility = true
        requestAccessibilityIfNeeded()
    }

}

struct StagePlaceholder: Equatable {
    let title: String
    let detail: String?
}

private struct MirroringNavigationRail: View {
    let press: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.s1) {
            railButton(title: "Home", itemName: "Home Screen")
            railButton(title: "App Switcher", itemName: "App Switcher")
            railButton(title: "Spotlight", itemName: "Spotlight")
        }
        .padding(Theme.s1)
        .background(Theme.surface.opacity(0.78))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Theme.border.opacity(0.9), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    private func railButton(title: String, itemName: String) -> some View {
        Button(title) {
            press(itemName)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, Theme.s2)
        .frame(height: 26)
        .background(Theme.elevated.opacity(0.88))
        .clipShape(Capsule(style: .continuous))
    }
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
    var menuFittedIOSDeviceIDs: Set<String> = []
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

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(onChange: onChange,
                      onWindowFrameChange: onWindowFrameChange)
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
        private var lastReportedRect: CGRect?

        init(onChange: @escaping (CGRect) -> Void,
             onWindowFrameChange: @escaping () -> Void) {
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
            guard lastReportedRect.map({ !rectsEffectivelyEqual($0, axRect, tolerance: 1) }) ?? true else {
                return
            }
            lastReportedRect = axRect
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
