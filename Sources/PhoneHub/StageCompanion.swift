import AppKit
import PhoneHubCore

extension Stage {
    /// Focus layout for Companion: PhoneHub is the sidebar; mirror sits beside
    /// it at native size (no stage fit, no AX resize).
    func companionFocus(_ device: Device?) {
        cancelDockingTask()
        redockTask?.cancel()
        stageState.isDocked = false

        guard stageState.phoneHubFrame.width > 0, stageState.phoneHubFrame.height > 0 else {
            stageState.placeholder = StagePlaceholder(
                title: device.map { "Docking \(store.displayName(for: $0))..." } ?? "Select a device",
                detail: "Waiting for the PhoneHub window to be ready."
            )
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
                                                  detail: "Placing the mirror beside PhoneHub.")

        switch device.platform {
        case .android:
            launchAndroidCompanion(device)
        case .ios:
            dockIOSCompanion(device)
        }
    }

    private func launchAndroidCompanion(_ device: Device) {
        if scrcpyController.processIdentifier(for: device.id) != nil {
            stageState.isDocked = true
            stageState.placeholder = StagePlaceholder(title: store.displayName(for: device),
                                                      detail: "Mirror sits beside PhoneHub at native size.")
            scheduleDockSync()
            return
        }

        let defaultSize = CGSize(width: 360, height: 780)
        let origin = companionMirrorOrigin(
            phoneHubFrame: stageState.phoneHubFrame,
            mirrorSize: defaultSize,
            gap: StageLayout.companionGap,
            visibleFrame: axVisibleFrame(containing: stageState.phoneHubFrame)
        )
        let frame = CGRect(origin: origin, size: defaultSize)
        let process = scrcpyController.launch(serial: device.id, frame: frame)
        if process == nil, scrcpyController.lastState == .missingTool {
            stageState.placeholder = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
                                                      detail: "scrcpy not installed - brew install scrcpy")
        } else if process == nil {
            stageState.placeholder = StagePlaceholder(title: "Could not dock \(store.displayName(for: device))",
                                                      detail: "scrcpy failed to start.")
        } else {
            stageState.isDocked = true
            stageState.placeholder = StagePlaceholder(title: store.displayName(for: device),
                                                      detail: "Mirror sits beside PhoneHub at native size.")
            scheduleDockSync()
        }
    }

    private func dockIOSCompanion(_ device: Device) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            stageState.placeholder = StagePlaceholder(
                title: "Docking \(store.displayName(for: device))...",
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
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
                // Activate iPhone Mirroring if needed, then reposition only — never menu-fit.
                mirroringController.activate()
                try await Task.sleep(nanoseconds: 200_000_000)
                try dockWindowBeside(ownerName: "com.apple.ScreenContinuity",
                                     phoneHubFrame: stageState.phoneHubFrame,
                                     gap: StageLayout.companionGap,
                                     activate: false)
                guard !Task.isCancelled,
                      store.layout == .companion,
                      stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = true
                stageState.placeholder = StagePlaceholder(
                    title: store.displayName(for: device),
                    detail: "iPhone Mirroring sits beside PhoneHub at native size."
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      store.layout == .companion,
                      stageState.activeDevice?.id == device.id else { return }
                stageState.isDocked = false
                stageState.placeholder = StagePlaceholder(
                    title: "Could not dock \(store.displayName(for: device))",
                    detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    func resyncCompanionDockedWindow() async {
        guard stageState.isDocked,
              let device = stageState.activeDevice,
              stageState.activeDevice?.id == store.focusedDevice?.id,
              stageState.phoneHubFrame.width > 0,
              stageState.phoneHubFrame.height > 0 else {
            return
        }

        do {
            switch device.platform {
            case .ios:
                // Reposition ONLY — never menu-fit or AX-resize (same safe path as Focus resync).
                try dockWindowBeside(ownerName: "com.apple.ScreenContinuity",
                                     phoneHubFrame: stageState.phoneHubFrame,
                                     gap: StageLayout.companionGap,
                                     activate: false)
            case .android:
                guard let processIdentifier = scrcpyController.processIdentifier(for: device.id) else {
                    return
                }
                try dockWindowBeside(byTitle: "PhoneHub-\(device.id)",
                                     processIdentifier: processIdentifier,
                                     phoneHubFrame: stageState.phoneHubFrame,
                                     gap: StageLayout.companionGap)
            }
        } catch {
            stageState.isDocked = false
            stageState.placeholder = StagePlaceholder(
                title: "Could not dock \(store.displayName(for: device))",
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
