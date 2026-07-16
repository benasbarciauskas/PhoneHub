import SwiftUI
import PhoneHubCore

struct PinnedAutomationBar: View {
    @Bindable var store: AutomationStore
    var runner: AutomationRunner
    let focused: Device?
    let othersBusy: Bool
    let backend: AgentBackend
    let preferKnownSteps: Bool

    private var pinned: [Automation] {
        guard let focused else { return [] }
        return store.automations(for: focused.platform).filter(\.pinned)
    }

    var body: some View {
        if let focused, !pinned.isEmpty {
            HStack(spacing: Theme.s1) {
                ForEach(pinned) { automation in
                    Button {
                        runner.backend = backend
                        runner.preferKnownSteps = preferKnownSteps
                        runner.run(automation, on: focused, othersBusy: othersBusy)
                    } label: {
                        Label(automation.name, systemImage: "bolt.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.s2).frame(height: 26)
                    .background(Theme.elevated.opacity(0.9)).clipShape(Capsule())
                    .disabled(runner.isBusy || othersBusy)
                }
                if runner.isBusy {
                    Button("Stop") { runner.stop() }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.err).padding(.horizontal, Theme.s2)
                }
            }
            .padding(Theme.s2).background(Theme.surface.opacity(0.8)).clipShape(Capsule())
        }
    }
}
