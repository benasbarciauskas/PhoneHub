import PhoneHubCore
import SwiftUI

struct BuilderRecordingToolbar: View {
    @Bindable var draftStore: BuilderDraftStore
    var engine: AutomationEngine
    var runner: AutomationRunner
    let focused: Device?
    let chatBusy: Bool
    let backend: AgentBackend
    let addTap: () -> Void
    let insert: (BuilderInsertKind) -> Void
    let showSources: () -> Void

    @State private var recorder = HumanRecorder()
    @State private var recordedSteps: [AutomationStep] = []
    @State private var description = ""
    @State private var isStarting = false
    @State private var isDescribing = false
    @State private var errorMessage: String?
    @State private var startTask: Task<Void, Never>?
    @State private var descriptionTask: Task<Void, Never>?
    @AppStorage("builderHumanRecordingSafetyNoticeSeen")
    private var safetyNoticeSeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            toolbar
            if !safetyNoticeSeen && !recorder.isRecording {
                Label(
                    "Keystrokes typed into the phone are stored as plain text in the timeline. "
                    + "Do not record while entering passwords.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.system(size: 10))
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
            }
            if recorder.isRecording { recordingBanner }
            if !recorder.isRecording, !recordedSteps.isEmpty { recordingSummary }
            if !description.isEmpty { descriptionEditor }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: focused?.id) { _, _ in
            if recorder.isRecording { recorder.stop(reason: .builderClosed) }
        }
        .onDisappear {
            startTask?.cancel()
            descriptionTask?.cancel()
            recorder.stop(reason: .builderClosed)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.s2) {
            Text("Timeline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if recorder.isRecording {
                Button(action: stopRecording) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .foregroundStyle(Theme.err)
            } else {
                Button(action: startRecording) {
                    if isStarting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Record", systemImage: "record.circle")
                    }
                }
                .foregroundStyle(canRecord ? Theme.err : Theme.subtext.opacity(0.4))
                .disabled(!canRecord)
                .help("Record your actions in the focused mirror window")
            }
            Button(action: addTap) { Image(systemName: "hand.tap") }
                .help("Add tap")
                .disabled(recorder.isRecording)
            Menu {
                Button("Pause") { insert(.pause) }
                Button("Type text") { insert(.typeText) }
                Button("AI action") { insert(.aiAction) }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton)
            .help("Insert action")
            .disabled(recorder.isRecording)
            Button(action: showSources) { Image(systemName: "text.badge.plus") }
                .help("Text Sources")
                .disabled(recorder.isRecording)
            Button(role: .destructive) { draftStore.clear() } label: {
                Image(systemName: "trash")
            }
            .help("Clear draft")
            .disabled(draftStore.draft.steps.isEmpty || recorder.isRecording)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.subtext)
    }

    private var recordingBanner: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack(spacing: Theme.s1) {
                Circle().fill(Theme.err).frame(width: 8, height: 8)
                Text("Recording — interact with the mirror window")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(recorder.recordedStepCount) steps")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.subtext)
            }
            if let notice = recorder.notice {
                HStack {
                    Text(notice).font(.system(size: 10)).foregroundStyle(Theme.warn)
                    Button("Open System Settings") {
                        SystemPermissions.openInputMonitoringSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
            }
        }
        .padding(Theme.s2)
        .background(Theme.err.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMd).stroke(Theme.err.opacity(0.4)))
    }

    private var recordingSummary: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recorded \(recordedSteps.count) timeline steps")
                    .font(.system(size: 11, weight: .semibold))
                if let message = recorder.lastStopMessage {
                    Text(message).font(.system(size: 9)).foregroundStyle(Theme.subtext)
                }
            }
            Spacer()
            Button(action: describeRecording) {
                if isDescribing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Describe recording", systemImage: "sparkles")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .disabled(isDescribing || engine.isBusy || engine.isCondensing)
        }
        .padding(Theme.s2)
        .cardSurface(elevated: true)
    }

    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text("Recording description")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.subtext)
            TextField("What this recording does", text: $description, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var canRecord: Bool {
        guard let focused, focused.isReady || focused.platform == .ios else { return false }
        guard draftStore.draft.platform == nil
                || draftStore.draft.platform == focused.platform else { return false }
        return !isStarting && !runner.isBusy && !engine.isBusy && !engine.isCondensing && !chatBusy
    }

    private func startRecording() {
        guard canRecord, let device = focused else { return }
        safetyNoticeSeen = true
        recordedSteps = []
        description = ""
        errorMessage = nil
        isStarting = true
        startTask?.cancel()
        startTask = Task { @MainActor in
            defer { isStarting = false; startTask = nil }
            do {
                try await recorder.start(device: device) { steps in
                    do {
                        for step in steps {
                            try draftStore.append(step, platform: device.platform)
                        }
                        recordedSteps.append(contentsOf: steps)
                    } catch {
                        errorMessage = error.localizedDescription
                        recorder.stop(reason: .builderClosed)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        recorder.stop(reason: .user)
    }

    private func describeRecording() {
        guard !recordedSteps.isEmpty else { return }
        errorMessage = nil
        isDescribing = true
        descriptionTask?.cancel()
        let steps = recordedSteps
        descriptionTask = Task { @MainActor in
            defer { isDescribing = false; descriptionTask = nil }
            do {
                description = try await engine.describeRecording(rawSteps: steps, backend: backend)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
