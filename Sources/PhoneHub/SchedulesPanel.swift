import SwiftUI
import PhoneHubCore

/// Simple schedules manager: list, enable/disable, next-run, add, delete.
struct SchedulesPanel: View {
    @Bindable var scheduleStore: ScheduleStore
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
                Text("Schedules").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.subtext)
                .help("Add schedule")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Runs only while PhoneHub is open. Skips if a preset, automation, or chat is already running.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            if scheduleStore.schedules.isEmpty {
                Text("No schedules yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(scheduleStore.schedules) { schedule in
                        ScheduleRow(schedule: schedule) {
                            scheduleStore.setEnabled(schedule, enabled: !schedule.enabled)
                        } onDelete: {
                            scheduleStore.delete(schedule)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Theme.s4)
        .frame(minWidth: 440, minHeight: 380)
        .background(Theme.surface)
        .sheet(isPresented: $showingAdd) {
            AddScheduleSheet(
                scheduleStore: scheduleStore,
                presetStore: presetStore,
                automationStore: automationStore,
                devices: devices,
                displayName: displayName,
                focused: focused
            )
        }
    }
}

private struct ScheduleRow: View {
    let schedule: Schedule
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var nextRunLabel: String {
        let now = Date()
        if Scheduler.isDue(schedule, now: now, lastFired: schedule.lastFired) {
            return "Due now"
        }
        let next = Scheduler.nextFireDate(schedule, after: now)
        return next.formatted(date: .abbreviated, time: .shortened)
    }

    private var cadenceLabel: String {
        switch schedule.cadence {
        case .interval:
            return "Every \(max(1, schedule.intervalMinutes)) min"
        case .daily:
            let h = String(format: "%02d", schedule.hour)
            let m = String(format: "%02d", schedule.minute)
            return "Daily \(h):\(m)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("\(schedule.targetKind.rawValue) · \(schedule.deviceName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
                Text(cadenceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
                if schedule.enabled {
                    Text("Next: \(nextRunLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("Disabled")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subtext)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { schedule.enabled },
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
            .help("Delete schedule")
        }
        .padding(.vertical, Theme.s1)
        .listRowBackground(Theme.elevated.opacity(0.4))
    }
}

private struct AddScheduleSheet: View {
    @Bindable var scheduleStore: ScheduleStore
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
    @State private var cadence: ScheduleCadence = .interval
    @State private var intervalMinutes = 60
    @State private var hour = 9
    @State private var minute = 0

    private var canSave: Bool {
        guard selectedDeviceId != nil else { return false }
        switch targetKind {
        case .preset: return selectedPresetId != nil
        case .automation: return selectedAutomationId != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack {
                Text("New Schedule").font(.headline).foregroundStyle(Theme.text)
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

            Picker("When", selection: $cadence) {
                Text("Interval").tag(ScheduleCadence.interval)
                Text("Daily").tag(ScheduleCadence.daily)
            }
            .pickerStyle(.segmented)

            if cadence == .interval {
                Stepper("Every \(intervalMinutes) min", value: $intervalMinutes, in: 1...24 * 60)
            } else {
                HStack {
                    Stepper("Hour \(hour)", value: $hour, in: 0...23)
                    Stepper("Min \(minute)", value: $minute, in: 0...59)
                }
            }
        }
        .padding(Theme.s4)
        .frame(width: 400)
        .background(Theme.surface)
        .onAppear {
            selectedDeviceId = focused?.id ?? devices.first?.id
            selectedPresetId = presetStore.presets.first?.id
            selectedAutomationId = automationStore.automations.first?.id
        }
    }

    private func save() {
        guard let deviceId = selectedDeviceId,
              let device = devices.first(where: { $0.id == deviceId }) else { return }

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

        let schedule = Schedule(
            name: name,
            targetKind: targetKind,
            targetId: targetId,
            deviceId: device.id,
            deviceName: displayName(device),
            cadence: cadence,
            intervalMinutes: intervalMinutes,
            hour: hour,
            minute: minute,
            enabled: true
        )
        scheduleStore.add(schedule)
        dismiss()
    }
}
