import SwiftUI
import PhoneHubCore

struct Sidebar: View {
    @Bindable var store: DeviceStore
    @Bindable var presetStore: PresetStore
    @Bindable var automationStore: AutomationStore
    @Bindable var textSourceStore: TextSourceStore
    @Bindable var builderDraftStore: BuilderDraftStore
    @Bindable var historyStore: RunHistoryStore
    @Bindable var scheduleStore: ScheduleStore
    @Bindable var triggerStore: TriggerStore
    var engine: AutomationEngine
    var chatEngine: ChatEngine
    var automationRunner: AutomationRunner
    @Binding var agentBackend: AgentBackend
    var llmSettings: LLMSettingsModel

    @State private var lowerPanel: LowerPanel = .presets
    @State private var renamingDevice: Device?
    @State private var renameText = ""
    @State private var showingSettings = false
    @State private var showingAddDevice = false
    @State private var switchMessage: String?
    @State private var isSwitchingIPhone = false

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
                    Button { showingAddDevice = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).foregroundStyle(Theme.subtext)
                        .help("Add device")
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(Theme.subtext)
                    Menu {
                        Picker("Agent backend", selection: $agentBackend) {
                            ForEach(AgentBackend.allCases, id: \.self) { backend in
                                Text(backend.rawValue.capitalized).tag(backend)
                            }
                        }
                        Divider()
                        Button("LLM Settings…") { showingSettings = true }
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
                if store.layout == .wall {
                    Picker("Wall preset", selection: $store.wallGridPreset) {
                        ForEach(WallGridPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
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
                        DeviceRow(device: device,
                                  displayName: store.displayName(for: device),
                                  selected: device.id == store.focusedDevice?.id)
                            .onTapGesture { withAnimation(Theme.selection) { store.setFocused(device) } }
                            .contextMenu {
                                if device.platform == .ios,
                                   device.id != store.focusedDevice?.id {
                                    Button("Switch iPhone Mirroring to this device") {
                                        Task { await switchIPhoneMirroring(to: device) }
                                    }
                                    .disabled(isSwitchingIPhone)
                                    Divider()
                                }
                                Button("Rename") {
                                    renameText = store.displayName(for: device)
                                    renamingDevice = device
                                }
                                Divider()
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

            // Short labels so five segments fit the 240pt sidebar without overflow.
            Picker("Panel", selection: $lowerPanel) {
                Text("Presets").tag(LowerPanel.presets)
                Text("Autos").tag(LowerPanel.automations)
                Text("Chat").tag(LowerPanel.chat)
                Text("Hist").tag(LowerPanel.history)
                Text("Notifs").tag(LowerPanel.notifications)
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
                                 agentBackend: agentBackend,
                                 preferKnownSteps: llmSettings.preferKnownSteps)
                }
            case .automations:
                ScrollView {
                    AutomationsPanel(store: automationStore, textSourceStore: textSourceStore,
                                     runner: automationRunner,
                                     agentEngine: engine, chatBusy: chatEngine.isBusy,
                                     focused: store.focusedDevice, backend: agentBackend,
                                     preferKnownSteps: llmSettings.preferKnownSteps,
                                     deviceRefs: store.connectedDeviceRefs)
                }
            case .chat:
                ChatPanel(engine: chatEngine, presetEngine: engine,
                          automationBusy: automationRunner.isBusy,
                          focused: store.focusedDevice, backend: agentBackend)
            case .history:
                ScrollView {
                    HistoryPanel(
                        historyStore: historyStore,
                        scheduleStore: scheduleStore,
                        triggerStore: triggerStore,
                        focused: store.focusedDevice,
                        displayName: { store.displayName(for: $0) },
                        presetStore: presetStore,
                        automationStore: automationStore,
                        devices: store.devices
                    )
                }
            case .notifications:
                ScrollView {
                    NotificationsPanel(focused: store.focusedDevice)
                }
            }
        }
        .frame(width: StageLayout.sidebarWidth)
        .background(Theme.surface)
        .alert("Rename Device", isPresented: Binding(
            get: { renamingDevice != nil },
            set: { if !$0 { renamingDevice = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let device = renamingDevice else { return }
                store.setName(deviceId: device.id, name: renameText)
            }
        } message: {
            Text("Leave the name empty to use the discovered model name.")
        }
        .sheet(isPresented: $showingSettings) {
            LLMSettingsView(settings: llmSettings)
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceSheet(store: store)
        }
        .alert("iPhone Mirroring", isPresented: Binding(
            get: { switchMessage != nil },
            set: { if !$0 { switchMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(switchMessage ?? "")
        }
    }

    /// Drive System Settings → Desktop & Dock iPhone popup, then re-focus/dock.
    private func switchIPhoneMirroring(to device: Device) async {
        guard device.platform == .ios, !isSwitchingIPhone else { return }
        isSwitchingIPhone = true
        defer { isSwitchingIPhone = false }

        var names: [String] = []
        let display = store.displayName(for: device)
        if !display.isEmpty { names.append(display) }
        if device.model != display, !device.model.isEmpty { names.append(device.model) }

        let result = await IPhoneSwitcher.switchMirroring(toDeviceNames: names)
        switch result {
        case .switched:
            store.setFocused(device)
            store.refresh()
        default:
            if let message = result.userMessage {
                switchMessage = message
            }
        }
    }
}

private struct AddDeviceSheet: View {
    @Bindable var store: DeviceStore
    @Environment(\.dismiss) private var dismiss

    @State private var platform: Platform = .android
    @State private var hostPort = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack {
                Text("Add Device").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Picker("Platform", selection: $platform) {
                Text("Android").tag(Platform.android)
                Text("iOS").tag(Platform.ios)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if platform == .android {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    Text("Host:port")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    TextField("192.168.1.50:5555", text: $hostPort)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)
                        .onSubmit { Task { await connect() } }
                    Text("Connect over Wi‑Fi after enabling wireless debugging on the phone.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    HStack {
                        Spacer()
                        Button(isConnecting ? "Connecting…" : "Connect") {
                            Task { await connect() }
                        }
                        .disabled(isConnecting || hostPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                Text("iOS devices connect automatically via iPhone Mirroring — they can't be added manually. Pair the iPhone in the iPhone Mirroring app.")
                    .font(.callout)
                    .foregroundStyle(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Theme.err : Theme.ok)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.s6)
        .frame(width: 360)
        .background(Theme.surface)
        .onChange(of: platform) { _, _ in
            statusMessage = nil
            statusIsError = false
        }
    }

    private func connect() async {
        let value = hostPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isConnecting = true
        statusMessage = nil
        defer { isConnecting = false }

        let result = await store.connectAndroid(hostPort: value)
        switch result {
        case .success(let message):
            statusIsError = false
            statusMessage = message
        case .failure(let error):
            statusIsError = true
            statusMessage = error.message
        }
    }
}

private enum LowerPanel: Hashable {
    case presets
    case automations
    case chat
    case history
    case notifications
}

private struct DeviceRow: View {
    let device: Device
    let displayName: String
    let selected: Bool

    var statusColor: Color {
        sidebarStatusColor(for: device)
    }

    var body: some View {
        HStack(spacing: Theme.s2) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
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
