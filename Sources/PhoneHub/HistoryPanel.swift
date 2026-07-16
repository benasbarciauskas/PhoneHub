import SwiftUI
import PhoneHubCore

/// Per-focused-device run history (newest first). Shown as a lower-panel tab.
struct HistoryPanel: View {
    @Bindable var historyStore: RunHistoryStore
    @Bindable var scheduleStore: ScheduleStore
    @Bindable var triggerStore: TriggerStore
    let focused: Device?
    let displayName: (Device) -> String
    var presetStore: PresetStore
    var automationStore: AutomationStore
    var devices: [Device]

    @State private var selected: RunRecord?
    @State private var showingSchedules = false
    @State private var showingTriggers = false

    private var records: [RunRecord] {
        guard let focused else { return [] }
        return historyStore.records(deviceId: focused.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Text("History").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showingTriggers = true
                } label: {
                    Label("Triggers", systemImage: "bolt")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Manage event triggers (Android)")
                Button {
                    showingSchedules = true
                } label: {
                    Label("Schedules", systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Manage scheduled runs")
            }
            .padding(.horizontal, Theme.s3)

            if focused == nil {
                Text("Select a device to see its run history.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .padding(.horizontal, Theme.s3)
                    .padding(.top, Theme.s2)
            } else if records.isEmpty {
                Text("No runs yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .padding(.horizontal, Theme.s3)
                    .padding(.top, Theme.s2)
            } else {
                LazyVStack(spacing: Theme.s1) {
                    ForEach(records) { record in
                        HistoryRow(record: record)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = record }
                    }
                }
                .padding(.horizontal, Theme.s2)
            }
        }
        .padding(.bottom, Theme.s3)
        .sheet(item: $selected) { record in
            HistoryDetailSheet(record: record)
        }
        .sheet(isPresented: $showingSchedules) {
            SchedulesPanel(
                scheduleStore: scheduleStore,
                presetStore: presetStore,
                automationStore: automationStore,
                devices: devices,
                displayName: displayName,
                focused: focused
            )
        }
        .sheet(isPresented: $showingTriggers) {
            TriggersPanel(
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

private struct HistoryRow: View {
    let record: RunRecord

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.subtext)
            }
            Spacer(minLength: 4)
            OutcomeBadge(outcome: record.outcome)
        }
        .padding(.vertical, Theme.s2)
        .padding(.horizontal, Theme.s2)
        .background(Theme.elevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
    }
}

struct OutcomeBadge: View {
    let outcome: RunOutcome

    private var color: Color {
        switch outcome {
        case .finished: return Theme.ok
        case .failed: return Theme.err
        case .stopped: return Theme.warn
        }
    }

    private var label: String {
        switch outcome {
        case .finished: return "ok"
        case .failed: return "fail"
        case .stopped: return "stop"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

private struct HistoryDetailSheet: View {
    let record: RunRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("\(record.kind.rawValue) · \(record.deviceName)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                OutcomeBadge(outcome: record.outcome)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text(record.startedAt.formatted(date: .complete, time: .standard)
                 + " → "
                 + record.endedAt.formatted(date: .omitted, time: .standard))
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.s1) {
                    ForEach(Array(record.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Theme.s4)
        .frame(minWidth: 420, minHeight: 360)
        .background(Theme.surface)
    }
}
