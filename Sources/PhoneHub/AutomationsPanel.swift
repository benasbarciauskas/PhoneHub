import SwiftUI
import PhoneHubCore

struct AutomationsPanel: View {
    @Bindable var store: AutomationStore
    var runner: AutomationRunner
    var agentEngine: AutomationEngine
    let chatBusy: Bool
    let focused: Device?
    let backend: AgentBackend

    @State private var editing: Automation?
    @State private var showingSheet = false

    private var visible: [Automation] {
        guard let focused else { return store.automations }
        return store.automations(for: focused.platform)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text("Automations").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button { create() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.subtext)
                    .disabled(focused == nil)
            }
            .padding(.horizontal, Theme.s3)

            if case let .pausedNeedsRecalibrate(_, label) = runner.state,
               let automation = visible.first(where: { $0.id == runner.runningAutomationID }) {
                HStack(spacing: Theme.s2) {
                    Text("Couldn't find ‘\(label)’")
                        .font(.system(size: 10)).foregroundStyle(Theme.warn).lineLimit(2)
                    Spacer()
                    Button("Re-calibrate") { recalibrate(automation) }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 10))
                }
                .padding(Theme.s2).cardSurface(elevated: true).padding(.horizontal, Theme.s2)
            }

            if visible.isEmpty {
                Text(focused == nil ? "Focus a device to create an automation"
                                    : "No automations for this platform")
                    .font(.caption).foregroundStyle(Theme.subtext)
                    .padding(.horizontal, Theme.s3)
            }

            VStack(spacing: Theme.s1) {
                ForEach(visible) { automation in
                    AutomationRow(
                        automation: automation,
                        isRunning: runner.isBusy && runner.runningAutomationID == automation.id,
                        isPaused: isPaused(automation),
                        canRun: canRun(automation),
                        run: { run(automation) },
                        stop: { runner.stop() },
                        edit: { editing = automation; showingSheet = true },
                        recalibrate: { recalibrate(automation) },
                        duplicate: { store.duplicate(automation) },
                        delete: { store.delete(automation) }
                    )
                }
            }
            .padding(.horizontal, Theme.s2)
        }
        .padding(.bottom, Theme.s3)
        .sheet(isPresented: $showingSheet) {
            if let editing {
                AutomationEditSheet(automation: editing) { result in
                    if store.automations.contains(where: { $0.id == result.id }) { store.update(result) }
                    else { store.add(result) }
                }
            }
        }
    }

    private func create() {
        guard let focused else { return }
        editing = Automation(name: "New automation", platform: focused.platform, steps: [])
        showingSheet = true
    }

    private func canRun(_ automation: Automation) -> Bool {
        guard let focused, focused.platform == automation.platform else { return false }
        return !runner.isBusy && !agentEngine.isBusy && !chatBusy
    }

    private func run(_ automation: Automation) {
        guard let focused else { return }
        runner.backend = backend
        runner.run(automation, on: focused, othersBusy: agentEngine.isBusy || chatBusy)
    }

    private func isPaused(_ automation: Automation) -> Bool {
        guard automation.id == runner.runningAutomationID else { return false }
        if case .pausedNeedsRecalibrate = runner.state { return true }
        return false
    }

    private func recalibrate(_ automation: Automation) {
        guard let focused else { return }
        var updated = automation
        updated.bindings[focused.id] = nil
        store.update(updated)
        runner.clearResult()
        if let goal = updated.sourceGoal, !agentEngine.isBusy, !chatBusy {
            agentEngine.runAdhoc(goal: goal, on: focused, backend: backend)
        }
    }
}

private struct AutomationRow: View {
    let automation: Automation
    let isRunning: Bool
    let isPaused: Bool
    let canRun: Bool
    let run: () -> Void
    let stop: () -> Void
    let edit: () -> Void
    let recalibrate: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: Theme.s2) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.s1) {
                        if automation.pinned { Image(systemName: "star.fill").font(.system(size: 9)) }
                        Text(automation.name).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    Text("\(automation.steps.count) steps · \(loopLabel)")
                        .font(.system(size: 10)).foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if isPaused {
                Button("Re-calibrate", action: recalibrate)
                    .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(Theme.warn)
            } else {
                Button(action: isRunning ? stop : run) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle((canRun || isRunning) ? Theme.accent : Theme.subtext.opacity(0.4))
                .disabled(!canRun && !isRunning)
            }
        }
        .padding(.vertical, Theme.s2).padding(.horizontal, Theme.s3)
        .contextMenu {
            Button("Run", action: run).disabled(!canRun)
            Button("Edit", action: edit)
            Button("Duplicate", action: duplicate)
            if isPaused { Button("Re-calibrate", action: recalibrate) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var loopLabel: String {
        switch automation.loop {
        case .once: return "once"
        case .times(let count): return "×\(count)"
        case .forever: return "forever"
        }
    }
}
