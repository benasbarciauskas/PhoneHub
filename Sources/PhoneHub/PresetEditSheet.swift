import SwiftUI
import PhoneHubCore

/// Add / edit sheet for a preset, with an AI ✨ Refine button on the Goal field.
struct PresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let original: Preset?
    let focusedDevice: Device?
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
         focusedDevice: Device? = nil,
         engine: AutomationEngine,
         onSave: @escaping (Preset) -> Void) {
        self.original = preset
        self.focusedDevice = focusedDevice
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

    private var editedPreset: Preset {
        var platforms: [Platform] = []
        if ios { platforms.append(.ios) }
        if android { platforms.append(.android) }
        return Preset(
            id: original?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            goal: goal.trimmingCharacters(in: .whitespaces),
            app: app.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                : app.trimmingCharacters(in: .whitespaces),
            platforms: platforms,
            maxSteps: maxSteps,
            backend: backend
        )
    }

    private var previewDevice: Device {
        if let focusedDevice { return focusedDevice }
        if ios {
            return Device(id: "PREVIEW-IOS", platform: .ios, model: "iPhone",
                          osVersion: "Preview", status: "connected")
        }
        return Device(id: "PREVIEW-ANDROID", platform: .android, model: "Android",
                      osVersion: "Preview", status: "device")
    }

    private var payloadPreview: String {
        presetPayloadPreview(preset: editedPreset, device: previewDevice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(original == nil ? "New Preset" : "Edit Preset")
                .font(.headline).foregroundStyle(Theme.text)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s3) {
                    field("Name") {
                        TextField("Open Instagram", text: $name).textFieldStyle(.roundedBorder)
                    }
                    field("Goal") {
                        VStack(alignment: .leading, spacing: Theme.s1) {
                            HStack(alignment: .top, spacing: Theme.s2) {
                                TextEditor(text: $goal)
                                    .font(.system(size: 13))
                                    .frame(minHeight: 100)
                                    .padding(4)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Theme.border)
                                    }
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
                                Text(refineError).font(.system(size: 10))
                                    .foregroundStyle(Theme.err).lineLimit(2)
                            }
                        }
                    }
                    field("App (optional)") {
                        TextField("Instagram", text: $app).textFieldStyle(.roundedBorder)
                    }

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
                                Text(choice.displayName).tag(Optional(choice))
                            }
                        }
                        .labelsHidden()
                    }

                    field("What the LLM receives") {
                        TextEditor(text: .constant(payloadPreview))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(4)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border)
                            }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(editedPreset)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(Theme.s6)
        .frame(width: 560, height: 680)
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
