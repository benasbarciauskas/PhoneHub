import AppKit
import PhoneHubCore

extension Stage {
    func syncWallIOS(_ device: Device, rect: CGRect, didRequestAccessibility: inout Bool) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityPromptIfNeeded(didRequestAccessibility: &didRequestAccessibility)
            stageState.wallPlaceholders[device.id] = StagePlaceholder(
                title: store.displayName(for: device),
                detail: "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
            )
            return
        }

        if dockingTaskIsWall, dockingTaskDeviceID == device.id {
            stageState.wallPlaceholders[device.id] = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
                                                                      detail: nil)
            return
        }

        if stageState.wallIOSDeviceID == device.id {
            dockWallIOS(device, rect: rect)
            return
        }

        cancelDockingTask()
        stageState.wallPlaceholders[device.id] = StagePlaceholder(title: "Docking \(store.displayName(for: device))...",
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
                stageState.wallPlaceholders[device.id] = StagePlaceholder(title: store.displayName(for: device),
                                                                          detail: nil)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.layout == .wall else { return }
                stageState.wallPlaceholders[device.id] = StagePlaceholder(
                    title: store.displayName(for: device),
                    detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    func dockWallIOS(_ device: Device, rect: CGRect) {
        cancelDockingTask()
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
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.layout == .wall else { return }
                stageState.wallPlaceholders[device.id] = StagePlaceholder(
                    title: store.displayName(for: device),
                    detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
                stageState.wallIOSDeviceID = nil
                scheduleDockSync()
            }
        }
    }

    func ensureWallTileOrder() {
        var order = store.wallTileOrder
        var occupiedSlots = Set(order.values)
        var nextSlot = 0
        for device in readyWallDevices where order[device.id] == nil {
            while occupiedSlots.contains(nextSlot) { nextSlot += 1 }
            order[device.id] = nextSlot
            occupiedSlots.insert(nextSlot)
        }
        if order != store.wallTileOrder {
            store.wallTileOrder = order
        }
    }

    func swapWallTiles(from: String, to: String) {
        guard from != to else { return }
        let swapped = swapSlots(order: store.wallTileOrder, from: from, to: to)
        guard swapped != store.wallTileOrder else { return }
        store.wallTileOrder = swapped
    }

    func setWallZoom(deviceID: String, scale: CGFloat) {
        store.wallZoomByDeviceID[deviceID] = min(1, max(0.35, scale))
    }

    func stopWall() {
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

    func requestAccessibilityPromptIfNeeded(didRequestAccessibility: inout Bool) {
        guard !didRequestAccessibility else { return }
        didRequestAccessibility = true
        requestAccessibilityIfNeeded()
    }
}
