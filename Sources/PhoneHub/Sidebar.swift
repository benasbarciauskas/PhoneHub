import SwiftUI
import PhoneHubCore

struct Sidebar: View {
    @Bindable var store: DeviceStore
    @Bindable var presetStore: PresetStore
    var engine: AutomationEngine
    var chatEngine: ChatEngine
    @Binding var agentBackend: AgentBackend

    @State private var lowerPanel: LowerPanel = .presets

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Devices").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Picker("Layout", selection: $store.layout) {
                    ForEach(StageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 112)
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
                Menu {
                    Picker("Agent backend", selection: $agentBackend) {
                        ForEach(AgentBackend.allCases, id: \.self) { backend in
                            Text(backend.rawValue.capitalized).tag(backend)
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Theme.s3).padding(.top, Theme.s3)

            if store.toolMissing {
                Text("adb not found — `brew install android-platform-tools`")
                    .font(.caption).foregroundStyle(Theme.warn)
                    .padding(.horizontal, Theme.s3)
            }

            ScrollView {
                VStack(spacing: Theme.s1) {
                    ForEach(store.devices) { device in
                        DeviceRow(device: device, selected: device.id == store.focusedDevice?.id)
                            .onTapGesture { withAnimation(Theme.selection) { store.setFocused(device) } }
                    }
                    if store.devices.isEmpty && !store.toolMissing {
                        Text("No devices connected").font(.caption)
                            .foregroundStyle(Theme.subtext).padding(.top, Theme.s4)
                    }
                }
                .padding(.horizontal, Theme.s2)
            }
            .frame(maxHeight: 280)

            Divider().overlay(Theme.border).padding(.horizontal, Theme.s3)

            Picker("Panel", selection: $lowerPanel) {
                Text("Presets").tag(LowerPanel.presets)
                Text("Chat").tag(LowerPanel.chat)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.s3)

            switch lowerPanel {
            case .presets:
                ScrollView {
                    PresetsPanel(store: presetStore, engine: engine,
                                 chatBusy: chatEngine.isBusy, focused: store.focusedDevice,
                                 agentBackend: agentBackend)
                }
            case .chat:
                ChatPanel(engine: chatEngine, presetEngine: engine,
                          focused: store.focusedDevice, backend: agentBackend)
            }
        }
        .frame(width: 240)
        .background(Theme.surface)
    }
}

private enum LowerPanel: Hashable {
    case presets
    case chat
}

private struct DeviceRow: View {
    let device: Device
    let selected: Bool

    var statusColor: Color {
        sidebarStatusColor(for: device)
    }

    var body: some View {
        HStack(spacing: Theme.s2) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.model).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(device.platform == .android ? "Android \(device.osVersion)" : "iOS \(device.osVersion)")
                    .font(.system(size: 11)).foregroundStyle(Theme.subtext)
                if device.platform == .ios, device.status == "notConnected" {
                    Text("not connected")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.subtext.opacity(0.72))
                }
            }
            Spacer()
        }
        .padding(.vertical, Theme.s2).padding(.horizontal, Theme.s3)
        .background(selected ? Theme.elevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
    }
}

enum SidebarStatusColorRole: Equatable {
    case ok
    case warn
    case err
}

func sidebarStatusColorRole(for device: Device) -> SidebarStatusColorRole {
    if device.platform == .ios {
        return device.status == "connected" ? .ok : .warn
    }

    switch device.status {
    case "device": return .ok
    case "unauthorized": return .warn
    default: return .err
    }
}

func sidebarStatusColor(for device: Device) -> Color {
    switch sidebarStatusColorRole(for: device) {
    case .ok: return Theme.ok
    case .warn: return Theme.warn
    case .err: return Theme.err
    }
}
