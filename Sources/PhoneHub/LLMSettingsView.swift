import SwiftUI
import PhoneHubCore

struct LLMSettingsView: View {
    @Bindable var settings: LLMSettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyEntry = ""

    private var backend: AgentBackend { settings.selectedBackend }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack {
                Text("LLM Settings").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            field("Default backend") {
                Picker("Default backend", selection: backendBinding) {
                    ForEach(AgentBackend.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .labelsHidden()
            }

            if backend.isAPI {
                field("Model") {
                    TextField("Model", text: modelBinding).textFieldStyle(.roundedBorder)
                }
                field("API key") {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        SecureField("Enter \(backend.displayName) API key", text: $keyEntry)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        HStack {
                            Text(settings.keyStatus(for: backend))
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                            Spacer()
                            Button("Clear key") {
                                settings.clearKey(for: backend)
                                keyEntry = ""
                            }
                            .disabled(settings.keyStatus(for: backend) == "not set")
                            Button("Save key", action: saveKey)
                                .disabled(keyEntry.isEmpty)
                        }
                    }
                }
                Toggle(isOn: visionBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vision mode (send screenshots to the model)")
                        Text("API backends only — claude/codex CLIs use their own vision.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .toggleStyle(.switch)
            } else {
                Text("\(backend.displayName) uses its existing CLI login.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }

            Divider()

            field("iOS screen describer") {
                Picker("Screen describer", selection: screenDescriberBinding) {
                    ForEach(ScreenDescriberMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(SkillsStatus.mirroirSkillsInstalled()
                     ? "iOS skills: installed ✓"
                     : "iOS skills: not installed — run scripts/setup-skills.sh")
                Text(DetectionStatus.elementDetectionLine())
                Text(DetectionStatus.visionDescriberHint)
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.subtext)

            if let message = settings.statusMessage {
                Text(message).font(.caption).foregroundStyle(Theme.err)
            }
        }
        .padding(Theme.s6)
        .frame(width: 430)
        .background(Theme.surface)
    }

    private var backendBinding: Binding<AgentBackend> {
        Binding(
            get: { settings.selectedBackend },
            set: {
                settings.selectBackend($0)
                keyEntry = ""
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.model(for: backend) },
            set: { settings.setModel($0, for: backend) }
        )
    }

    private var visionBinding: Binding<Bool> {
        Binding(
            get: { settings.visionEnabled },
            set: { settings.setVision($0) }
        )
    }

    private var screenDescriberBinding: Binding<ScreenDescriberMode> {
        Binding(
            get: { settings.screenDescriberMode },
            set: { settings.setScreenDescriberMode($0) }
        )
    }

    private func saveKey() {
        if settings.saveKey(keyEntry, for: backend) { keyEntry = "" }
    }

    private func field<Content: View>(_ label: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.subtext)
            content()
        }
    }
}
