import PhoneHubCore
import SwiftUI

struct BuilderView: View {
    @Bindable var draftStore: BuilderDraftStore
    @Bindable var textSourceStore: TextSourceStore
    @Bindable var automationStore: AutomationStore
    var engine: AutomationEngine
    var runner: AutomationRunner
    let focused: Device?
    let chatBusy: Bool
    let backend: AgentBackend
    let preferKnownSteps: Bool

    @State private var request = ""
    @State private var messages: [BuilderMessage] = []
    @State private var activeMessageID: UUID?
    @State private var activePlatform: Platform?
    @State private var tapRequest: TapPickerRequest?
    @State private var showingSources = false
    @State private var showingSave = false
    @State private var automationName = ""
    @State private var alertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Builder").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                if let platform = draftStore.draft.platform {
                    Text(platform.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.subtext)
                }
            }

            inputBox
            messageList
            timelineToolbar
            timeline
            runControls
            runnerStatus
        }
        .sheet(item: $tapRequest) { item in
            ManualTapPicker(device: item.device, existingStep: item.step) { step in
                do {
                    if item.step == nil {
                        try draftStore.append(step, platform: item.device.platform)
                    } else {
                        draftStore.update(step)
                    }
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showingSources) {
            TextSourcesSheet(store: textSourceStore)
        }
        .alert("Save as Automation", isPresented: $showingSave) {
            TextField("Automation name", text: $automationName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveAutomation() }
        } message: {
            Text("The current timeline and text-source bindings will be saved.")
        }
        .alert("Builder", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: engine.state) { _, state in handleEngineState(state) }
    }

    private var inputBox: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            TextField("Describe one next action…", text: $request, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { submitAction() }
            HStack {
                Button(action: submitAction) {
                    if engine.isBuilderAction && engine.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Add action", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSubmit ? Theme.accent : Theme.subtext.opacity(0.4))
                .disabled(!canSubmit)
                Spacer()
                if engine.isBuilderAction && engine.isBusy {
                    Button("Stop") { engine.stop() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.err)
                }
            }
            if let mismatch = platformMismatchMessage {
                Text(mismatch).font(.system(size: 10)).foregroundStyle(Theme.warn)
            }
        }
        .padding(Theme.s2)
        .cardSurface()
    }

    @ViewBuilder
    private var messageList: some View {
        if !messages.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    ForEach(messages.suffix(8)) { message in
                        HStack(alignment: .top, spacing: Theme.s1) {
                            Image(systemName: message.status.icon)
                                .foregroundStyle(message.status.color)
                                .frame(width: 13)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(message.request).font(.system(size: 10, weight: .medium))
                                Text(message.status.detail)
                                    .font(.system(size: 9)).foregroundStyle(Theme.subtext)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 92)
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: Theme.s2) {
            Text("Timeline").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Button { addTap() } label: { Image(systemName: "hand.tap") }
                .help("Add tap")
            Menu {
                Button("Pause") { insert(.pause, at: nil) }
                Button("Type text") { insert(.typeText, at: nil) }
                Button("AI action") { insert(.aiAction, at: nil) }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton)
            .help("Insert action")
            Button { showingSources = true } label: { Image(systemName: "text.badge.plus") }
                .help("Text Sources")
            Button(role: .destructive) { draftStore.clear() } label: {
                Image(systemName: "trash")
            }
            .help("Clear draft")
            .disabled(draftStore.draft.steps.isEmpty)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.subtext)
    }

    @ViewBuilder
    private var timeline: some View {
        if draftStore.draft.steps.isEmpty {
            Text("Add a tap, pause, text, AI action, or describe the next action above.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, minHeight: 64)
                .cardSurface(elevated: true)
        } else {
            List {
                ForEach(Array(draftStore.draft.steps.enumerated()), id: \.element.id) { index, step in
                    BuilderTimelineRow(
                        step: step,
                        index: index,
                        draftStore: draftStore,
                        textSourceStore: textSourceStore,
                        editTap: beginEditTap,
                        insert: { kind, position in insert(kind, at: position) }
                    )
                }
                .onMove(perform: draftStore.move)
                .onDelete(perform: draftStore.delete)
            }
            .listStyle(.plain)
            .frame(height: 300)
        }
    }

    private var runControls: some View {
        HStack(spacing: Theme.s2) {
            Button {
                automationName = "Builder automation"
                showingSave = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(draftStore.draft.steps.isEmpty)
            Button(action: runTimeline) {
                Label("Run timeline", systemImage: "play.fill")
            }
            .disabled(!canRunTimeline)
            if runner.isBusy {
                Button("Stop") { runner.stop() }.foregroundStyle(Theme.err)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .font(.system(size: 11, weight: .semibold))
    }

    @ViewBuilder
    private var runnerStatus: some View {
        if runner.runningAutomationID != nil || !runner.log.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(runner.log.suffix(5).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.subtext).lineLimit(2)
                }
            }
            .padding(Theme.s2)
            .cardSurface(elevated: true)
        }
    }

    private var canSubmit: Bool {
        guard let focused, focused.isReady || focused.platform == .ios else { return false }
        guard draftStore.draft.platform == nil || draftStore.draft.platform == focused.platform else {
            return false
        }
        return !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !engine.isBusy && !runner.isBusy && !chatBusy
    }

    private var canRunTimeline: Bool {
        guard let focused, draftStore.draft.platform == focused.platform else { return false }
        return !draftStore.draft.steps.isEmpty && !runner.isBusy && !engine.isBusy && !chatBusy
    }

    private var platformMismatchMessage: String? {
        guard let expected = draftStore.draft.platform, let focused,
              expected != focused.platform else { return nil }
        return "Draft is pinned to \(expected.rawValue). Focus that platform or clear the draft."
    }

    private func submitAction() {
        guard canSubmit, let focused else { return }
        let clean = request.trimmingCharacters(in: .whitespacesAndNewlines)
        request = ""
        if !engine.isBusy { engine.dismissResult() }
        engine.clearCapture()
        let message = BuilderMessage(request: clean, status: .running)
        messages.append(message)
        activeMessageID = message.id
        activePlatform = focused.platform
        engine.runBuilderAction(goal: clean, on: focused, backend: backend,
                                preferKnownSteps: preferKnownSteps)
    }

    private func handleEngineState(_ state: AutomationState) {
        guard engine.isBuilderAction, let messageID = activeMessageID else { return }
        switch state {
        case .finished:
            let steps = automationSteps(from: engine.lastCapture)
            if steps.count == 1, let step = steps.first, let platform = activePlatform {
                do {
                    try draftStore.append(step, platform: platform)
                    finishMessage(messageID, with: .ok(automationStepTitle(step) + ": "
                                                      + automationStepSummary(step)))
                } catch {
                    finishMessage(messageID, with: .failed(error.localizedDescription))
                }
            } else {
                finishMessage(messageID, with: .failed(
                    steps.isEmpty ? "No UI action was produced." : "The agent produced more than one UI action."
                ))
            }
            resetBuilderRun()
        case .failed(let message):
            finishMessage(messageID, with: .failed(message))
            resetBuilderRun()
        case .stopped:
            finishMessage(messageID, with: .failed("Stopped."))
            resetBuilderRun()
        case .awaitingInput:
            engine.stop()
        case .idle, .running: break
        }
    }

    private func finishMessage(_ id: UUID, with status: BuilderMessageStatus) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].status = status
    }

    private func resetBuilderRun() {
        activeMessageID = nil
        activePlatform = nil
        engine.clearCapture()
        engine.dismissResult()
    }

    private func addTap() {
        guard let focused else { alertMessage = "Focus a device first."; return }
        guard draftStore.draft.platform == nil || draftStore.draft.platform == focused.platform else {
            alertMessage = platformMismatchMessage
            return
        }
        tapRequest = TapPickerRequest(device: focused, step: nil)
    }

    private func beginEditTap(_ step: AutomationStep) {
        guard let focused else { alertMessage = "Focus a device first."; return }
        guard draftStore.draft.platform == focused.platform else {
            alertMessage = platformMismatchMessage ?? "Focus a matching device first."
            return
        }
        tapRequest = TapPickerRequest(device: focused, step: step)
    }

    private func insert(_ kind: BuilderInsertKind, at index: Int?) {
        guard let focused else { alertMessage = "Focus a device first."; return }
        let step: AutomationStep
        switch kind {
        case .pause: step = .wait(id: UUID(), ms: 500)
        case .typeText: step = .typeText(id: UUID(), text: "")
        case .aiAction: step = .aiStep(id: UUID(), prompt: "")
        }
        do {
            try draftStore.insert(step, at: index ?? draftStore.draft.steps.count,
                                  platform: focused.platform)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveAutomation() {
        do {
            let cleanName = automationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else {
                alertMessage = "Automation name is required."
                return
            }
            try validateBuilderTimeline(draftStore.draft, sources: textSourceStore.sources)
            guard let automation = draftStore.automation(named: cleanName) else {
                throw BuilderTimelineValidationError.emptyTimeline
            }
            automationStore.add(automation)
            alertMessage = "Saved “\(automation.name)”."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func runTimeline() {
        guard let focused else { return }
        do {
            try validateBuilderTimeline(draftStore.draft, sources: textSourceStore.sources)
            guard let automation = draftStore.automation(named: "Builder draft") else {
                throw BuilderTimelineValidationError.emptyTimeline
            }
            runner.clearResult()
            runner.backend = backend
            runner.preferKnownSteps = preferKnownSteps
            runner.run(automation, on: focused, othersBusy: engine.isBusy || chatBusy)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct TapPickerRequest: Identifiable {
    let id = UUID()
    let device: Device
    let step: AutomationStep?
}

private struct BuilderMessage: Identifiable {
    let id = UUID()
    let request: String
    var status: BuilderMessageStatus
}

private enum BuilderMessageStatus {
    case running
    case ok(String)
    case failed(String)

    var icon: String {
        switch self {
        case .running: return "clock"
        case .ok: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .running: return Theme.warn
        case .ok: return Theme.ok
        case .failed: return Theme.err
        }
    }

    var detail: String {
        switch self {
        case .running: return "Running one action…"
        case .ok(let detail), .failed(let detail): return detail
        }
    }
}
