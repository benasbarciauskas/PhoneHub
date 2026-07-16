import AppKit
import Observation
import SwiftUI
import PhoneHubCore

struct Stage: View {
    @Bindable var store: DeviceStore
    @Bindable var automationStore: AutomationStore
    var automationRunner: AutomationRunner
    var presetEngine: AutomationEngine
    var chatEngine: ChatEngine
    let agentBackend: AgentBackend

    @State var scrcpyController = ScrcpyController()
    @State var mirroringController = MirroringController()
    @State var stageState = StageState()
    @State var dockingTask: Task<Void, Never>?
    @State var dockingTaskDeviceID: String?
    @State var dockingTaskID: UUID?
    @State var dockingTaskIsWall = false
    @State var redockTask: Task<Void, Never>?
    @State var isSyncingDock = false

    let wallInset: CGFloat = 16
    let wallSpacing: CGFloat = 12
    let wallControlStripHeight: CGFloat = 48

    var body: some View {
        ZStack {
            Theme.bg
            if store.layout == .wall {
                WallGridView(devices: wallDevices,
                             placeholders: stageState.wallPlaceholders,
                             displayNames: wallDisplayNames,
                             preset: store.wallGridPreset,
                             zoomByDeviceID: store.wallZoomByDeviceID,
                             inset: wallInset,
                             spacing: wallSpacing,
                             onSwap: swapWallTiles,
                             onZoom: setWallZoom)
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

            PinnedAutomationBar(store: automationStore, runner: automationRunner,
                                focused: store.focusedDevice,
                                othersBusy: presetEngine.isBusy || chatEngine.isBusy,
                                backend: agentBackend)
                .padding(.top, Theme.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .onChange(of: store.wallGridPreset) { _, _ in
            if store.layout == .wall { scheduleDockSync() }
        }
        .onChange(of: store.wallTileOrder) { _, _ in
            if store.layout == .wall { scheduleDockSync() }
        }
        .onChange(of: store.wallZoomByDeviceID) { _, _ in
            if store.layout == .wall { scheduleDockSync() }
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

    var readyWallDevices: [Device] {
        store.devices.filter { device in
            switch device.platform {
            case .android:
                return device.isReady
            case .ios:
                return device.status == "connected"
            }
        }
    }

    var wallDevices: [Device] {
        let ordered = readyWallDevices.enumerated().sorted { lhs, rhs in
            let lhsKey = (store.wallTileOrder[lhs.element.id] ?? Int.max, lhs.offset)
            let rhsKey = (store.wallTileOrder[rhs.element.id] ?? Int.max, rhs.offset)
            return lhsKey < rhsKey
        }.map(\.element)
        return Array(ordered.prefix(store.wallGridPreset.capacity))
    }

    var wallDisplayNames: [String: String] {
        wallDevices.reduce(into: [:]) { names, device in
            names[device.id] = store.displayName(for: device)
        }
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

    func syncLayout() {
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
            stageState.placeholder = StagePlaceholder(title: device.map { "Docking \(store.displayName(for: $0))..." } ?? "Select a device",
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

        if let placeholder = stageNotConnectedIOSPlaceholder(for: device,
                                                              displayName: store.displayName(for: device)) {
            stageState.placeholder = placeholder
            return
        }

        guard device.isReady || device.platform == .ios else {
            stageState.placeholder = StagePlaceholder(title: "\(store.displayName(for: device)) is not ready",
                                                      detail: "Current status: \(device.status)")
            return
        }

        stageState.placeholder = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
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
            stageState.placeholder = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
                                                      detail: "scrcpy not installed - brew install scrcpy")
        } else if process == nil {
            stageState.placeholder = StagePlaceholder(title: "Could not dock \(store.displayName(for: device))",
                                                      detail: "scrcpy failed to start.")
        } else {
            stageState.isDocked = true
            stageState.placeholder = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
                                                      detail: "Mirror window launched into the stage rectangle.")
        }
    }

    private func dockIOS(_ device: Device) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            stageState.placeholder = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
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
                stageState.placeholder = StagePlaceholder(title: store.displayName(for: device),
                                                          detail: "iPhone Mirroring is positioned in the stage rectangle.")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = false
                stageState.placeholder = StagePlaceholder(title: "Could not dock \(store.displayName(for: device))",
                                                          detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func scheduleDockSync() {
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
            stageState.placeholder = StagePlaceholder(title: "Could not dock \(store.displayName(for: device))",
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
        ensureWallTileOrder()
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
                                  preset: store.wallGridPreset,
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
                        title: store.displayName(for: device),
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
        let contentRect = tileContentRect(in: rect, footerHeight: wallControlStripHeight)
        let dockRect = zoomedTileRect(in: contentRect, scale: store.wallZoomByDeviceID[device.id] ?? 1)
        guard isAccessibilityTrusted() else {
            requestAccessibilityPromptIfNeeded(didRequestAccessibility: &didRequestAccessibility)
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: store.displayName(for: device),
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
            return
        }

        if !stageState.wallAndroidSerials.contains(device.id) {
            let process = scrcpyController.launch(serial: device.id, frame: dockRect)
            if process == nil, scrcpyController.lastState == .missingTool {
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: store.displayName(for: device),
                                                                          detail: "scrcpy not installed - brew install scrcpy")
                return
            } else if process == nil {
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: store.displayName(for: device),
                                                                          detail: "scrcpy failed to start.")
                return
            }
            stageState.wallAndroidSerials.insert(device.id)
        }

        do {
            guard let processIdentifier = scrcpyController.processIdentifier(for: device.id) else {
                throw WindowDockError.windowNotFound("PhoneHub-\(device.id)")
            }
            try dockWindow(byTitle: "PhoneHub-\(device.id)", processIdentifier: processIdentifier, into: dockRect)
            stageState.wallPlaceholders[device.id] = StagePlaceholder(title: store.displayName(for: device),
                                                                      detail: nil)
        } catch {
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: store.displayName(for: device),
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            if case WindowDockError.windowNotFound = error {
                scheduleDockSync()
            }
        }
    }

    func cancelDockingTask() {
        dockingTask?.cancel()
        dockingTask = nil
        dockingTaskDeviceID = nil
        dockingTaskID = nil
        dockingTaskIsWall = false
    }

}
