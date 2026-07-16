import AppKit
import Observation
import SwiftUI
import PhoneHubCore

struct StagePlaceholder: Equatable {
    let title: String
    let detail: String?
}

struct MirroringNavigationRail: View {
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

func stageNotConnectedIOSPlaceholder(for device: Device,
                                     displayName: String? = nil) -> StagePlaceholder? {
    guard device.platform == .ios, device.status == "notConnected" else {
        return nil
    }

    return StagePlaceholder(title: "\(displayName ?? device.model) — not connected",
                            detail: "Bring it near + unlock (same Apple ID), or it may be mirrored elsewhere. macOS mirrors one iPhone at a time.")
}

@Observable
@MainActor
final class StageState {
    var activeDevice: Device?
    var stageRect: CGRect = .zero
    /// PhoneHub window frame in AX coordinates (for Companion side-docking).
    var phoneHubFrame: CGRect = .zero
    var isDocked = false
    var wallAndroidSerials: Set<String> = []
    var wallIOSDeviceID: String?
    var menuFittedIOSDeviceIDs: Set<String> = []
    var wallPlaceholders: [String: StagePlaceholder] = [:]
    var placeholder = StagePlaceholder(title: "Select a device",
                                       detail: "Connected devices appear in the sidebar.")
}

struct WallGridView: View {
    let devices: [Device]
    let placeholders: [String: StagePlaceholder]
    let displayNames: [String: String]
    let preset: WallGridPreset
    let zoomByDeviceID: [String: CGFloat]
    let inset: CGFloat
    let spacing: CGFloat
    let onSwap: (String, String) -> Void
    let onZoom: (String, CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            let visibleDevices = devices.isEmpty ? [Device(id: "empty",
                                                           platform: .ios,
                                                           model: "No ready devices",
                                                           osVersion: "",
                                                           status: "connected")] : devices
            let rects = gridTileRects(count: visibleDevices.count,
                                      preset: devices.isEmpty ? .auto : preset,
                                      within: CGRect(origin: .zero, size: proxy.size),
                                      inset: inset,
                                      spacing: spacing)
            ForEach(Array(zip(visibleDevices, rects)), id: \.0.id) { device, rect in
                tile(for: device)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    @ViewBuilder
    private func tile(for device: Device) -> some View {
        let tile = WallTileView(
            device: device,
            placeholder: placeholders[device.id] ?? StagePlaceholder(
                title: displayNames[device.id] ?? device.model,
                detail: nil
            ),
            zoom: zoomByDeviceID[device.id] ?? 1,
            onZoom: { onZoom(device.id, $0) }
        )
        if device.id == "empty" {
            tile
        } else {
            tile
                .draggable(device.id)
                .dropDestination(for: String.self) { deviceIDs, _ in
                    guard let sourceID = deviceIDs.first else { return false }
                    onSwap(sourceID, device.id)
                    return true
                }
        }
    }
}

private struct WallTileView: View {
    let device: Device
    let placeholder: StagePlaceholder
    let zoom: CGFloat
    let onZoom: (CGFloat) -> Void

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
            Spacer(minLength: 0)
            if device.id != "empty" {
                if device.platform == .android {
                    HStack(spacing: Theme.s2) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: Binding(get: { zoom }, set: onZoom), in: 0.35...1)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.subtext)
                    .help("Resize this Android mirror within its tile")
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subtext)
                        .help("iPhone Mirroring can't be resized")
                }
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

struct PlaceholderView: View {
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

struct StageRectReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void
    /// Full PhoneHub window frame in AX coordinates, then a move/resize signal.
    let onWindowFrameChange: (CGRect) -> Void

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
        var onWindowFrameChange: (CGRect) -> Void
        private weak var observedWindow: NSWindow?
        private var observerTokens: [NSObjectProtocol] = []
        private var lastReportedRect: CGRect?
        private var lastReportedWindowFrame: CGRect?

        init(onChange: @escaping (CGRect) -> Void,
             onWindowFrameChange: @escaping (CGRect) -> Void) {
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
            reportWindowFrame(window)
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

        private func reportWindowFrame(_ window: NSWindow) {
            let axFrame = window.frame.convertedToAXCoordinates()
            guard lastReportedWindowFrame.map({ !rectsEffectivelyEqual($0, axFrame, tolerance: 1) }) ?? true else {
                return
            }
            lastReportedWindowFrame = axFrame
            DispatchQueue.main.async {
                self.onWindowFrameChange(axFrame)
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
