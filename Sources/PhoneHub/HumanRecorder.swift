import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import PhoneHubCore

enum HumanRecorderError: Error, LocalizedError {
    case accessibilityRequired
    case mirrorAppUnavailable
    case mirrorWindowUnavailable
    case deviceSizeUnavailable
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Enable Accessibility for PhoneHub before recording."
        case .mirrorAppUnavailable:
            return "The focused device mirror is not running."
        case .mirrorWindowUnavailable:
            return "The focused device mirror window could not be found."
        case .deviceSizeUnavailable:
            return "The device coordinate size could not be determined."
        case .eventTapUnavailable:
            return "macOS could not start the listen-only input recorder."
        }
    }
}

enum HumanRecorderStopReason: Equatable {
    case user
    case mirrorDeactivated
    case mirrorQuit
    case builderClosed
    case appQuit

    var message: String {
        switch self {
        case .user: return "Recording stopped."
        case .mirrorDeactivated: return "Recording stopped when the mirror lost focus."
        case .mirrorQuit: return "Recording stopped because the mirror quit."
        case .builderClosed: return "Recording stopped when Builder closed."
        case .appQuit: return "Recording stopped because PhoneHub quit."
        }
    }
}

private struct HumanRecordingTarget {
    let device: Device
    let application: NSRunningApplication
    let window: AXUIElement
    let deviceSize: CGSize
    var frame: CGRect
}

@Observable
@MainActor
final class HumanRecorder {
    private(set) var isRecording = false
    private(set) var recordsKeyboard = false
    private(set) var notice: String?
    private(set) var lastStopMessage: String?
    private(set) var recordedStepCount = 0

    private var target: HumanRecordingTarget?
    private var translator = HumanRecordingTranslator()
    private var onSteps: (([AutomationStep]) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var idleTimer: Timer?
    private var observerTokens: [NSObjectProtocol] = []
    private var targetHasActivated = false
    private var lastGeometryRefresh: TimeInterval = 0

    func start(device: Device, onSteps: @escaping ([AutomationStep]) -> Void) async throws {
        if isRecording { stop(reason: .user) }
        guard isAccessibilityTrusted() else { throw HumanRecorderError.accessibilityRequired }

        let deviceSize = try await resolveDeviceSize(device)
        guard let resolved = resolveTarget(device: device, deviceSize: deviceSize) else {
            throw HumanRecorderError.mirrorWindowUnavailable
        }

        target = resolved
        translator = HumanRecordingTranslator()
        self.onSteps = onSteps
        recordedStepCount = 0
        lastStopMessage = nil
        recordsKeyboard = SystemPermissions.inputMonitoringGranted
        notice = recordsKeyboard ? nil
            : "Keystrokes are unavailable. Recording mouse actions only."
        lastGeometryRefresh = ProcessInfo.processInfo.systemUptime

        guard installEventTap(includeKeyboard: recordsKeyboard) else {
            target = nil
            self.onSteps = nil
            throw HumanRecorderError.eventTapUnavailable
        }
        installLifecycleObservers()
        installIdleTimer()
        isRecording = true
        targetHasActivated = resolved.application.isActive
        resolved.application.activate()
    }

    func stop(reason: HumanRecorderStopReason = .user) {
        guard isRecording || eventTap != nil else { return }
        let finalSteps = translator.finish(at: ProcessInfo.processInfo.systemUptime)
        deliver(finalSteps)
        tearDownEventTap()
        removeLifecycleObservers()
        idleTimer?.invalidate()
        idleTimer = nil
        isRecording = false
        target = nil
        onSteps = nil
        targetHasActivated = false
        lastStopMessage = reason.message
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        guard isRecording, let target else { return }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }

        let time = TimeInterval(event.timestamp) / 1_000_000_000
        switch type {
        case .leftMouseDown, .leftMouseUp:
            guard let point = scopedMousePoint(event.location, target: target, time: time) else {
                return
            }
            let input: HumanRecordedEvent = type == .leftMouseDown
                ? .leftMouseDown(time: time, point: point)
                : .leftMouseUp(time: time, point: point)
            deliver(translator.consume(input))

        case .rightMouseDown:
            guard scopedMousePoint(event.location, target: target, time: time) != nil else { return }
            deliver(translator.consume(.rightMouseDown(time: time)))

        case .scrollWheel:
            guard scopedMousePoint(event.location, target: target, time: time) != nil else { return }
            let preciseX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let preciseY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let deltaX = preciseX == 0
                ? event.getDoubleValueField(.scrollWheelEventDeltaAxis2) : preciseX
            let deltaY = preciseY == 0
                ? event.getDoubleValueField(.scrollWheelEventDeltaAxis1) : preciseY
            deliver(translator.consume(.scroll(time: time, deltaX: deltaX, deltaY: deltaY)))

        case .keyDown:
            guard recordsKeyboard, keyScopeMatches(target) else { return }
            deliver(translator.consume(keyEvent(from: event, time: time)))

        case .flagsChanged:
            // Modifiers are observed for focus/scoping only. Recording them would
            // split printable text and has no standalone phone-step equivalent.
            guard recordsKeyboard, keyScopeMatches(target) else { return }

        default:
            break
        }
    }

    private func scopedMousePoint(
        _ globalPoint: CGPoint,
        target: HumanRecordingTarget,
        time: TimeInterval
    ) -> HumanRecordingPoint? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == target.application.processIdentifier,
              let hitWindow = axWindowUnderPoint(globalPoint),
              isSameAXElement(hitWindow, target.window) else { return nil }
        refreshGeometryIfNeeded(at: time)
        guard let current = self.target else { return nil }
        switch current.device.platform {
        case .ios:
            return mapIPhoneMirrorPoint(globalPoint: globalPoint, windowFrame: current.frame,
                                        contentSize: current.deviceSize)
        case .android:
            return mapAndroidMirrorPoint(globalPoint: globalPoint, windowFrame: current.frame,
                                         devicePixelSize: current.deviceSize)
        }
    }

    private func keyScopeMatches(_ target: HumanRecordingTarget) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.application.processIdentifier
            && isAXWindowFocused(target.window, processIdentifier: target.application.processIdentifier)
    }

    private func keyEvent(from event: CGEvent, time: TimeInterval) -> HumanRecordedEvent {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &actualLength,
            unicodeString: &characters
        )
        let value = String(utf16CodeUnits: characters, count: actualLength)
        return humanRecordedKeyEvent(
            time: time,
            keyCode: keyCode,
            text: value,
            hasCommandOrControl: !event.flags.intersection([.maskCommand, .maskControl]).isEmpty
        )
    }

    private func installEventTap(includeKeyboard: Bool) -> Bool {
        var types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .scrollWheel,
        ]
        if includeKeyboard { types += [.keyDown, .flagsChanged] }
        let mask = types.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << CGEventMask($1.rawValue))
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: humanRecorderEventCallback,
            userInfo: pointer
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func installIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.deliver(self.translator.consume(
                    .idle(time: ProcessInfo.processInfo.systemUptime)
                ))
            }
        }
    }

    private func installLifecycleObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.processIdentifier == self.target?.application.processIdentifier else { return }
                self.targetHasActivated = true
            }
        })
        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.targetHasActivated,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.processIdentifier == self.target?.application.processIdentifier else { return }
                self.stop(reason: .mirrorDeactivated)
            }
        })
        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.processIdentifier == self.target?.application.processIdentifier else { return }
                self.stop(reason: .mirrorQuit)
            }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: .appQuit) }
        })
    }

    private func removeLifecycleObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in observerTokens {
            workspace.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func refreshGeometryIfNeeded(at time: TimeInterval) {
        guard time - lastGeometryRefresh >= 0.1,
              var target, let frame = readAXFrame(target.window) else { return }
        target.frame = frame
        self.target = target
        lastGeometryRefresh = time
    }

    private func deliver(_ steps: [AutomationStep]) {
        guard !steps.isEmpty else { return }
        recordedStepCount += steps.count
        onSteps?(steps)
    }

    private func resolveDeviceSize(_ device: Device) async throws -> CGSize {
        switch device.platform {
        case .android:
            guard let size = await Task.detached(priority: .userInitiated, operation: {
                AndroidController.screenSize(serial: device.id)
            }).value else { throw HumanRecorderError.deviceSizeUnavailable }
            return size
        case .ios:
            let client = makePhoneMcpClient(for: .ios)
            do {
                try await client.start()
                defer { client.stop() }
                let status = try await client.callTool("status", arguments: [:], timeoutSeconds: 10)
                guard !status.isError, let size = parseMirroirWindowSize(status.text) else {
                    throw HumanRecorderError.deviceSizeUnavailable
                }
                return size
            } catch let error as HumanRecorderError {
                throw error
            } catch {
                throw HumanRecorderError.deviceSizeUnavailable
            }
        }
    }

    private func resolveTarget(device: Device, deviceSize: CGSize) -> HumanRecordingTarget? {
        let application: NSRunningApplication
        let window: AXUIElement
        switch device.platform {
        case .ios:
            guard let app = findIPhoneMirroringApp() else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let found = firstWindow(in: appElement) else { return nil }
            application = app
            window = found
        case .android:
            guard let found = findWindowTarget(title: "PhoneHub-\(device.id)") else { return nil }
            application = found.application
            window = found.window
        }
        guard let frame = readAXFrame(window) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.1)
        return HumanRecordingTarget(device: device, application: application,
                                    window: window, deviceSize: deviceSize, frame: frame)
    }

    private func findWindowTarget(
        title: String
    ) -> (application: NSRunningApplication, window: AXUIElement)? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }
        for info in windows {
            guard info[kCGWindowName] as? String == title,
                  (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let window = findWindow(title: title, processIdentifier: pid) else { continue }
            return (app, window)
        }
        return nil
    }
}

private func humanRecorderEventCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let recorder = Unmanaged<HumanRecorder>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
        recorder.receive(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
