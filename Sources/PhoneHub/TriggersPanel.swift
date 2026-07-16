import SwiftUI
import PhoneHubCore

/// Event-trigger manager: list, enable/disable, add, delete.
/// Android-only conditions; iOS targets show an explanatory note.
struct TriggersPanel: View {
    @Bindable var triggerStore: TriggerStore
    var presetStore: PresetStore
    var automationStore: AutomationStore
    let devices: [Device]
    let displayName: (Device) -> String
    let focused: Device?

    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Triggers").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.subtext)
                .help("Add trigger")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Fires only while PhoneHub is open (no background daemon). Android only — skips if a preset, automation, or chat is already running.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            if triggerStore.triggers.isEmpty {
                Text("No triggers yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(triggerStore.triggers) { trigger in
                        TriggerRow(trigger: trigger) {
                            triggerStore.setEnabled(trigger, enabled: !trigger.enabled)
                        } onDelete: {
                            triggerStore.delete(trigger)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Theme.s4)
        .frame(minWidth: 460, minHeight: 400)
        .background(Theme.surface)
        .sheet(isPresented: $showingAdd) {
            AddTriggerSheet(
                triggerStore: triggerStore,
                presetStore: presetStore,
                automationStore: automationStore,
                devices: devices,
                displayName: displayName,
                focused: focused
            )
        }
    }
}

private struct TriggerRow: View {
    let trigger: Trigger
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var conditionLabel: String {
        switch trigger.condition {
        case .notificationMatch(let pkg, let text):
            var parts: [String] = ["Notification"]
            if let pkg, !pkg.isEmpty { parts.append("pkg:\(pkg)") }
            if let text, !text.isEmpty { parts.append("text:\(text)") }
            return parts.joined(separator: " · ")
        case .appForeground(let pkg):
            return "App foreground · \(pkg)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trigger.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("\(trigger.targetKind.rawValue) · \(trigger.deviceName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
                Text(conditionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(2)
                if trigger.enabled {
                    if let last = trigger.lastFired {
                        Text("Last: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("Watching…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                } else {
                    Text("Disabled")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subtext)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { trigger.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.err.opacity(0.85))
            .help("Delete trigger")
        }
        .padding(.vertical, Theme.s1)
        .listRowBackground(Theme.elevated.opacity(0.4))
    }
}

private enum TriggerConditionKind: String, CaseIterable, Identifiable {
    case notificationMatch
    case appForeground
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notificationMatch: return "Notification"
        case .appForeground: return "App opens"
        }
    }
}

private struct AddTriggerSheet: View {
    @Bindable var triggerStore: TriggerStore
    var presetStore: PresetStore
    var automationStore: AutomationStore
    let devices: [Device]
    let displayName: (Device) -> String
    let focused: Device?

    @Environment(\.dismiss) private var dismiss

    @State private var targetKind: RunKind = .preset
    @State private var selectedPresetId: UUID?
    @State private var selectedAutomationId: UUID?
    @State private var selectedDeviceId: String?
    @State private var conditionKind: TriggerConditionKind = .notificationMatch
    @State private var packageContains = ""
    @State private var textContains = ""

    private var selectedDevice: Device? {
        devices.first(where: { $0.id == selectedDeviceId })
    }

    private var deviceIsIOS: Bool {
        selectedDevice?.platform == .ios
    }

    private var androidDevices: [Device] {
        devices.filter { $0.platform == .android }
    }

    private var canSave: Bool {
        guard !deviceIsIOS, selectedDeviceId != nil else { return false }
        if conditionKind == .appForeground {
            guard !packageContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        switch targetKind {
        case .preset: return selectedPresetId != nil
        case .automation: return selectedAutomationId != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack {
                Text("New Trigger").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }

            Picker("Type", selection: $targetKind) {
                Text("Preset").tag(RunKind.preset)
                Text("Automation").tag(RunKind.automation)
            }
            .pickerStyle(.segmented)

            if targetKind == .preset {
                Picker("Preset", selection: $selectedPresetId) {
                    Text("Select…").tag(Optional<UUID>.none)
                    ForEach(presetStore.presets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
            } else {
                Picker("Automation", selection: $selectedAutomationId) {
                    Text("Select…").tag(Optional<UUID>.none)
                    ForEach(automationStore.automations) { automation in
                        Text(automation.name).tag(Optional(automation.id))
                    }
                }
            }

            Picker("Device", selection: $selectedDeviceId) {
                Text("Select…").tag(Optional<String>.none)
                ForEach(devices) { device in
                    Text(displayName(device)).tag(Optional(device.id))
                }
            }

            if deviceIsIOS {
                Text("Triggers need Android (no iOS notification API).")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if androidDevices.isEmpty {
                Text("Connect an Android device to use event triggers.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }

            Picker("When", selection: $conditionKind) {
                ForEach(TriggerConditionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(deviceIsIOS)

            if conditionKind == .notificationMatch {
                TextField("Package contains (optional)", text: $packageContains)
                    .textFieldStyle(.roundedBorder)
                    .disabled(deviceIsIOS)
                TextField("Title/text contains (optional)", text: $textContains)
                    .textFieldStyle(.roundedBorder)
                    .disabled(deviceIsIOS)
                Text("Fires once when a new matching notification appears.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            } else {
                TextField("Package contains (required)", text: $packageContains)
                    .textFieldStyle(.roundedBorder)
                    .disabled(deviceIsIOS)
                Text("Fires once when that app becomes foreground.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
        }
        .padding(Theme.s4)
        .frame(width: 420)
        .background(Theme.surface)
        .onAppear {
            let android = focused?.platform == .android ? focused : androidDevices.first
            selectedDeviceId = android?.id ?? devices.first?.id
            selectedPresetId = presetStore.presets.first?.id
            selectedAutomationId = automationStore.automations.first?.id
        }
    }

    private func save() {
        guard let deviceId = selectedDeviceId,
              let device = devices.first(where: { $0.id == deviceId }),
              device.platform == .android else { return }

        let name: String
        let targetId: UUID
        switch targetKind {
        case .preset:
            guard let id = selectedPresetId,
                  let preset = presetStore.presets.first(where: { $0.id == id }) else { return }
            name = preset.name
            targetId = id
        case .automation:
            guard let id = selectedAutomationId,
                  let automation = automationStore.automations.first(where: { $0.id == id }) else { return }
            name = automation.name
            targetId = id
        }

        let condition: TriggerCondition
        switch conditionKind {
        case .notificationMatch:
            let pkg = packageContains.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = textContains.trimmingCharacters(in: .whitespacesAndNewlines)
            condition = .notificationMatch(
                packageContains: pkg.isEmpty ? nil : pkg,
                textContains: text.isEmpty ? nil : text
            )
        case .appForeground:
            let pkg = packageContains.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pkg.isEmpty else { return }
            condition = .appForeground(packageContains: pkg)
        }

        triggerStore.add(Trigger(
            name: name,
            enabled: true,
            deviceId: device.id,
            deviceName: displayName(device),
            targetKind: targetKind,
            targetId: targetId,
            condition: condition
        ))
        dismiss()
    }
}
