import SwiftUI
import PhoneHubCore

/// Presets list + live run view. Shown in the Sidebar below the device list.
struct PresetsPanel: View {
    @Bindable var store: PresetStore
    var engine: AutomationEngine
    let focused: Device?

    @State private var editing: Preset?
    @State private var showingSheet = false

    private var platform: Platform? { focused?.platform }

    private var visiblePresets: [Preset] {
        guard let platform else { return store.presets }
        return store.presets(for: platform)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Presets").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    editing = nil
                    showingSheet = true
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Theme.s3)

            if engine.isRunning || engine.runningPreset != nil {
                runView
                    .padding(.horizontal, Theme.s2)
            } else {
                listView
            }
        }
        .padding(.bottom, Theme.s3)
        .sheet(isPresented: $showingSheet) {
            PresetEditSheet(preset: editing) { result in
                if let existing = editing, existing.id == result.id {
                    store.update(result)
                } else {
                    store.add(result)
                }
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        VStack(spacing: Theme.s1) {
            if visiblePresets.isEmpty {
                Text(focused == nil ? "Connect a device to run presets"
                                    : "No presets for this platform")
                    .font(.caption).foregroundStyle(Theme.subtext)
                    .padding(.top, Theme.s2).padding(.horizontal, Theme.s3)
            }
            ForEach(visiblePresets) { preset in
                PresetRow(
                    preset: preset,
                    canRun: canRun(preset),
                    onRun: { if let device = focused { engine.run(preset: preset, on: device) } },
                    onEdit: { editing = preset; showingSheet = true },
                    onDelete: { store.delete(preset) }
                )
            }
        }
        .padding(.horizontal, Theme.s2)
    }

    private func canRun(_ preset: Preset) -> Bool {
        guard let focused, focused.isReady || focused.platform == .ios else { return false }
        guard preset.supports(focused.platform) else { return false }
        return !engine.isRunning
    }

    // MARK: - Running

    private var runView: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                ProgressView().controlSize(.small).opacity(engine.isRunning ? 1 : 0)
                Text(engine.runningPreset?.name ?? "Run")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if engine.isRunning {
                    Button("Stop") { engine.stop() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.err)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            if let action = engine.currentAction {
                Text(action)
                    .font(.system(size: 11)).foregroundStyle(Theme.subtext)
                    .lineLimit(1).truncationMode(.middle)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(engine.log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.subtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(Theme.s2)
                }
                .frame(height: 180)
                .cardSurface(elevated: true)
                .onChange(of: engine.log.count) { _, count in
                    if count > 0 { withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) } }
                }
            }
            if !engine.isRunning {
                Button("Done") {
                    engine.dismissResult()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(Theme.s3)
        .cardSurface()
    }
}

private struct PresetRow: View {
    let preset: Preset
    let canRun: Bool
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.s2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(preset.goal)
                    .font(.system(size: 10)).foregroundStyle(Theme.subtext)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Button(action: onRun) {
                Image(systemName: "play.fill").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canRun ? Theme.accent : Theme.subtext.opacity(0.4))
            .disabled(!canRun)
        }
        .padding(.vertical, Theme.s2).padding(.horizontal, Theme.s3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

/// Add / edit sheet for a preset.
private struct PresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: Preset?
    let onSave: (Preset) -> Void

    @State private var name: String
    @State private var goal: String
    @State private var app: String
    @State private var ios: Bool
    @State private var android: Bool
    @State private var maxSteps: Int

    init(preset: Preset?, onSave: @escaping (Preset) -> Void) {
        self.original = preset
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
        _goal = State(initialValue: preset?.goal ?? "")
        _app = State(initialValue: preset?.app ?? "")
        _ios = State(initialValue: preset?.platforms.contains(.ios) ?? true)
        _android = State(initialValue: preset?.platforms.contains(.android) ?? true)
        _maxSteps = State(initialValue: preset?.maxSteps ?? 40)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !goal.trimmingCharacters(in: .whitespaces).isEmpty
            && (ios || android)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(original == nil ? "New Preset" : "Edit Preset")
                .font(.headline).foregroundStyle(Theme.text)

            field("Name") { TextField("Open Instagram", text: $name).textFieldStyle(.roundedBorder) }
            field("Goal") {
                TextField("Plain-English instruction", text: $goal, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
            }
            field("App (optional)") { TextField("Instagram", text: $app).textFieldStyle(.roundedBorder) }

            field("Platforms") {
                HStack(spacing: Theme.s3) {
                    Toggle("iOS", isOn: $ios)
                    Toggle("Android", isOn: $android)
                }
            }
            field("Max steps") {
                Stepper("\(maxSteps)", value: $maxSteps, in: 1...200, step: 5)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var platforms: [Platform] = []
                    if ios { platforms.append(.ios) }
                    if android { platforms.append(.android) }
                    let result = Preset(
                        id: original?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        goal: goal.trimmingCharacters(in: .whitespaces),
                        app: app.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                            : app.trimmingCharacters(in: .whitespaces),
                        platforms: platforms,
                        maxSteps: maxSteps
                    )
                    onSave(result)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(Theme.s6)
        .frame(width: 380)
        .background(Theme.surface)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.subtext)
            content()
        }
    }
}
