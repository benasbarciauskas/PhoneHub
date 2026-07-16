import SwiftUI
import PhoneHubCore

/// Presets list + free-form command box + live run view. Shown in the Sidebar
/// below the device list.
struct PresetsPanel: View {
    @Bindable var store: PresetStore
    @Bindable var automationStore: AutomationStore
    var engine: AutomationEngine
    var chatBusy: Bool
    var automationBusy: Bool
    let focused: Device?
    let agentBackend: AgentBackend
    let preferKnownSteps: Bool

    @State private var editing: Preset?
    @State private var showingSheet = false
    @State private var prefillGoal = ""

    // Free-form command box.
    @State private var command = ""
    @State private var refineError: String?

    private var platform: Platform? { focused?.platform }

    private var visiblePresets: [Preset] {
        guard let platform else { return store.presets }
        return store.presets(for: platform)
    }

    private var canRunCommand: Bool {
        guard let focused, focused.isReady || focused.platform == .ios else { return false }
        return !engine.isBusy
            && !chatBusy
            && !automationBusy
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Presets").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button {
                    editing = nil
                    prefillGoal = ""
                    showingSheet = true
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
            }
            .padding(.horizontal, Theme.s3)

            if engine.isBusy || engine.runningPreset != nil {
                runView
                    .padding(.horizontal, Theme.s2)
            } else {
                commandBox
                    .padding(.horizontal, Theme.s2)
                listView
            }

            Text(SkillsStatus.mirroirSkillsInstalled()
                 ? "iOS skills: installed ✓"
                 : "iOS skills: not installed — run scripts/setup-skills.sh")
                .font(.system(size: 10))
                .foregroundStyle(Theme.subtext)
                .padding(.horizontal, Theme.s3)
        }
        .padding(.bottom, Theme.s3)
        .sheet(isPresented: $showingSheet) {
            PresetEditSheet(preset: editing, prefillGoal: prefillGoal,
                            focusedDevice: focused, engine: engine,
                            appPreferKnownSteps: preferKnownSteps) { result in
                if let existing = editing, existing.id == result.id {
                    store.update(result)
                } else {
                    store.add(result)
                }
            }
        }
    }

    // MARK: - Command box

    private var commandBox: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            TextField("Type a one-off command…", text: $command, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            HStack(spacing: Theme.s2) {
                Button {
                    if let device = focused {
                        let goal = command
                        command = ""
                        engine.runAdhoc(goal: goal, on: device, backend: agentBackend,
                                        preferKnownSteps: preferKnownSteps)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canRunCommand ? Theme.accent : Theme.subtext.opacity(0.4))
                .disabled(!canRunCommand)

                Button { refineCommand() } label: {
                    if engine.isRefining {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refine", systemImage: "sparkles").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.subtext)
                .disabled(engine.isRefining
                          || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button {
                    editing = nil
                    prefillGoal = command
                    showingSheet = true
                } label: {
                    Text("Save as preset").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.subtext)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let refineError {
                Text(refineError)
                    .font(.system(size: 10)).foregroundStyle(Theme.err)
                    .lineLimit(2)
            }
        }
        .padding(Theme.s2)
        .cardSurface()
    }

    private func refineCommand() {
        let text = command
        refineError = nil
        Task {
            do {
                let rewritten = try await engine.refine(text)
                command = rewritten
            } catch {
                refineError = "Refine failed: \(error.localizedDescription)"
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
                    onRun: {
                        if let device = focused {
                            engine.run(preset: preset, on: device, backend: agentBackend,
                                       preferKnownSteps: preferKnownSteps)
                        }
                    },
                    onEdit: { editing = preset; prefillGoal = ""; showingSheet = true },
                    onDuplicate: { store.duplicate(preset) },
                    onDelete: { store.delete(preset) }
                )
            }
        }
        .padding(.horizontal, Theme.s2)
    }

    private func canRun(_ preset: Preset) -> Bool {
        guard let focused, focused.isReady || focused.platform == .ios else { return false }
        guard preset.supports(focused.platform) else { return false }
        return !engine.isBusy && !chatBusy && !automationBusy
    }

    // MARK: - Running

    private var runView: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                ProgressView().controlSize(.small).opacity(engine.isRunning ? 1 : 0)
                Text(engine.runningPreset?.name ?? "Run")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if engine.isBusy {
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

            if case let .awaitingInput(question) = engine.state {
                AwaitingInputView(question: question) { engine.reply($0) }
            }

            if !engine.isBusy {
                if !engine.lastCapture.isEmpty, let focused, let preset = engine.runningPreset {
                    Button("Save as automation") {
                        let draft = automationDraft(from: engine.lastCapture,
                                                    platform: focused.platform,
                                                    name: "\(preset.name) automation",
                                                    sourceGoal: preset.goal)
                        automationStore.add(draft)
                        engine.clearCapture()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12, weight: .semibold))
                }
                Button("Done") { engine.dismissResult() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(Theme.s3)
        .cardSurface()
    }
}

/// The reply prompt shown while the agent is paused awaiting the user's answer.
private struct AwaitingInputView: View {
    let question: String
    let onSend: (String) -> Void
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s1) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Theme.accent).font(.system(size: 12))
                Text("Needs your input")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(question)
                .font(.system(size: 12)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.s2) {
                TextField("Your answer…", text: $reply, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder).font(.system(size: 12))
                Button("Send") {
                    let answer = reply
                    reply = ""
                    onSend(answer)
                }
                .buttonStyle(.plain)
                .foregroundStyle(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? Theme.subtext.opacity(0.4) : Theme.accent)
                .font(.system(size: 12, weight: .semibold))
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.s2)
        .cardSurface(elevated: true)
    }
}

private struct PresetRow: View {
    let preset: Preset
    let canRun: Bool
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.s2) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(preset.goal)
                        .font(.system(size: 10)).foregroundStyle(Theme.subtext)
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
            Button("Run", action: onRun).disabled(!canRun)
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
