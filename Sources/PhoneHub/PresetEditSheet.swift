import SwiftUI
import PhoneHubCore

/// Add / edit sheet for a preset, with an AI ✨ Refine button on the Goal field.
struct PresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: Preset?
    var engine: AutomationEngine
    let onSave: (Preset) -> Void

    @State private var name: String
    @State private var goal: String
    @State private var app: String
    @State private var ios: Bool
    @State private var android: Bool
    @State private var maxSteps: Int
    @State private var backend: AgentBackend?
    @State private var refineError: String?

    /// - Parameter prefillGoal: used (when there's no `preset`) to seed the Goal
    ///   from the free-form command box's "Save as preset".
    init(preset: Preset?,
         prefillGoal: String = "",
         engine: AutomationEngine,
         onSave: @escaping (Preset) -> Void) {
        self.original = preset
        self.engine = engine
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
        _goal = State(initialValue: preset?.goal ?? prefillGoal)
        _app = State(initialValue: preset?.app ?? "")
        _ios = State(initialValue: preset?.platforms.contains(.ios) ?? true)
        _android = State(initialValue: preset?.platforms.contains(.android) ?? true)
        _maxSteps = State(initialValue: preset?.maxSteps ?? 40)
        _backend = State(initialValue: preset?.backend)
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
                VStack(alignment: .leading, spacing: Theme.s1) {
                    HStack(alignment: .top, spacing: Theme.s2) {
                        TextField("Plain-English instruction", text: $goal, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        Button { refineGoal() } label: {
                            if engine.isRefining {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.subtext)
                        .help("Rewrite into a clear instruction")
                        .disabled(engine.isRefining
                                  || goal.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let refineError {
                        Text(refineError).font(.system(size: 10)).foregroundStyle(Theme.err).lineLimit(2)
                    }
                }
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
            field("Agent backend") {
                Picker("Agent backend", selection: $backend) {
                    Text("App default").tag(nil as AgentBackend?)
                    ForEach(AgentBackend.allCases, id: \.self) { choice in
                        Text(choice.rawValue.capitalized).tag(Optional(choice))
                    }
                }
                .labelsHidden()
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
                        maxSteps: maxSteps,
                        backend: backend
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

    private func refineGoal() {
        let text = goal
        refineError = nil
        Task {
            do {
                goal = try await engine.refine(text)
            } catch {
                refineError = "Refine failed: \(error.localizedDescription)"
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.subtext)
            content()
        }
    }
}
