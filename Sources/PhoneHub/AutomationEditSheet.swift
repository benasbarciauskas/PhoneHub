import SwiftUI
import PhoneHubCore

struct AutomationEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Automation
    @State private var condenseError: String?
    var engine: AutomationEngine
    let backend: AgentBackend
    /// Connected device model/label refs for switchDevice steps.
    let deviceRefs: [String]
    let save: (Automation) -> Void

    init(automation: Automation, engine: AutomationEngine, backend: AgentBackend,
         deviceRefs: [String] = [], save: @escaping (Automation) -> Void) {
        _draft = State(initialValue: automation)
        self.engine = engine
        self.backend = backend
        self.deviceRefs = deviceRefs
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Automation").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(Theme.subtext)
                Button("Save") { save(draft); dismiss() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.s3)
            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s3) {
                    TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
                    controls
                    if let condenseError {
                        Text(condenseError).font(.system(size: 11)).foregroundStyle(Theme.err)
                    }
                    HStack {
                        Text("Timeline").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        addMenu
                    }
                    ForEach(Array(draft.steps.indices), id: \.self) { index in
                        AutomationStepRow(step: stepBinding(index), index: index,
                                          canMoveUp: index > 0,
                                          canMoveDown: index + 1 < draft.steps.count,
                                          moveUp: { move(index, -1) },
                                          moveDown: { move(index, 1) },
                                          delete: { draft.steps.remove(at: index) },
                                          deviceRefs: deviceRefs)
                    }
                }
                .padding(Theme.s3)
            }
        }
        .frame(width: 620, height: 680)
        .background(Theme.bg)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Picker("Loop", selection: loopChoice) {
                    Text("Once").tag(LoopChoice.once)
                    Text("Times").tag(LoopChoice.times)
                    Text("Forever").tag(LoopChoice.forever)
                }
                .frame(width: 220)
                if case .times = draft.loop {
                    TextField("Count", value: loopCount, format: .number).frame(width: 70)
                }
            }
            if draft.rawSteps != nil {
                Toggle("Use condensed timeline", isOn: $draft.useCondensed)
            }
            Toggle("Share coordinates across devices", isOn: $draft.sharedCoordinates)
            Toggle("Pin as stage action", isOn: $draft.pinned)
            VStack(alignment: .leading, spacing: Theme.s1) {
                TextField("On success, run command", text: onSuccessCommand)
                    .textFieldStyle(.roundedBorder)
                Text("Runs after every step completes successfully.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            if draft.rawSteps != nil {
                Button { condense() } label: {
                    if engine.isCondensing {
                        HStack { ProgressView().controlSize(.small); Text("Condensing…") }
                    } else {
                        Label("Condense raw capture", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .disabled(engine.isCondensing || engine.isBusy)
            }
        }
        .font(.system(size: 12)).foregroundStyle(Theme.text)
        .padding(Theme.s3).cardSurface()
    }

    private var addMenu: some View {
        Menu {
            Button("Launch app") { add(.launchApp(id: UUID(), name: "App")) }
            Button("Tap") { add(.tap(id: UUID(), label: "Target", x: nil, y: nil)) }
            Button("Double tap") { add(.doubleTap(id: UUID(), label: "Target", x: nil, y: nil)) }
            Button("Long press") { add(.longPress(id: UUID(), label: "Target", x: nil, y: nil, durationMs: 800)) }
            Button("Type text") { add(.typeText(id: UUID(), text: "")) }
            Button("Press key") { add(.pressKey(id: UUID(), key: "ENTER")) }
            Button("Swipe") { add(.swipe(id: UUID(), direction: "up")) }
            Button("Press Home") { add(.pressHome(id: UUID())) }
            Button("Press Back") { add(.pressBack(id: UUID())) }
            Button("Press App Switcher") { add(.pressAppSwitcher(id: UUID())) }
            Button("Scroll to") { add(.scrollTo(id: UUID(), text: "", direction: "down")) }
            Button("Open URL") { add(.openURL(id: UUID(), url: "https://")) }
            Button("Wait") { add(.wait(id: UUID(), ms: 500)) }
            Button("AI step") { add(.aiStep(id: UUID(), prompt: "")) }
            Button("Switch device") {
                let initial = deviceRefs.first ?? ""
                add(.switchDevice(id: UUID(), deviceRef: initial))
            }
        } label: { Label("Add step", systemImage: "plus") }
        .menuStyle(.borderlessButton).foregroundStyle(Theme.accent)
    }

    private func add(_ step: AutomationStep) { draft.steps.append(step) }
    private func condense() {
        guard let rawSteps = draft.rawSteps else { return }
        condenseError = nil
        let goal = draft.sourceGoal ?? draft.name
        Task {
            do {
                let condensed = try await engine.condense(goal: goal, rawSteps: rawSteps,
                                                          backend: backend)
                draft.steps = condensed
                draft.useCondensed = true
            } catch {
                condenseError = error.localizedDescription
            }
        }
    }
    private func stepBinding(_ index: Int) -> Binding<AutomationStep> {
        Binding(get: { draft.steps[index] }, set: { draft.steps[index] = $0 })
    }
    private func move(_ index: Int, _ offset: Int) {
        draft.steps.swapAt(index, index + offset)
    }

    private enum LoopChoice: Hashable { case once, times, forever }
    private var loopChoice: Binding<LoopChoice> {
        Binding(get: {
            switch draft.loop { case .once: return .once; case .times: return .times; case .forever: return .forever }
        }, set: {
            switch $0 { case .once: draft.loop = .once; case .times: draft.loop = .times(2); case .forever: draft.loop = .forever }
        })
    }
    private var loopCount: Binding<Int> {
        Binding(get: { if case let .times(count) = draft.loop { return count }; return 2 },
                set: { draft.loop = .times(max(1, $0)) })
    }
    private var onSuccessCommand: Binding<String> {
        Binding(
            get: { draft.onSuccessCommand ?? "" },
            set: { draft.onSuccessCommand = $0.isEmpty ? nil : $0 }
        )
    }
}
