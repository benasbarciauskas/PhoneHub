import SwiftUI
import PhoneHubCore

struct Sidebar: View {
    @Bindable var store: DeviceStore
    @Bindable var presetStore: PresetStore
    @Bindable var automationStore: AutomationStore
    var engine: AutomationEngine
    var chatEngine: ChatEngine
    var automationRunner: AutomationRunner
    @Binding var agentBackend: AgentBackend

    @State private var lowerPanel: LowerPanel = .presets

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            VStack(spacing: Theme.s2) {
                HStack {
                    Text("Devices")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .layoutPriority(1)
                    Spacer()
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
                Picker("Layout", selection: $store.layout) {
                    ForEach(StageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
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
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    store.remove(deviceId: device.id)
                                }
                            }
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
                Text("Automations").tag(LowerPanel.automations)
                Text("Chat").tag(LowerPanel.chat)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.s3)

            switch lowerPanel {
            case .presets:
                ScrollView {
                    PresetsPanel(store: presetStore, automationStore: automationStore, engine: engine,
                                 chatBusy: chatEngine.isBusy, automationBusy: automationRunner.isBusy,
                                 focused: store.focusedDevice,
                                 agentBackend: agentBackend)
                }
            case .automations:
                ScrollView {
                    AutomationsPanel(store: automationStore, runner: automationRunner,
                                     agentEngine: engine, chatBusy: chatEngine.isBusy,
                                     focused: store.focusedDevice, backend: agentBackend)
                }
            case .chat:
                ChatPanel(engine: chatEngine, presetEngine: engine,
                          automationBusy: automationRunner.isBusy,
                          focused: store.focusedDevice, backend: agentBackend)
            }
        }
        .frame(width: 240)
        .background(Theme.surface)
    }
}

private enum LowerPanel: Hashable {
    case presets
    case automations
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
                Text(device.model)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
