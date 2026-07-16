import AppKit
import SwiftUI
import PhoneHubCore

struct LLMSettingsView: View {
    @Bindable var settings: LLMSettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyEntry = ""
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false

    private var backend: AgentBackend { settings.selectedBackend }

    var body: some View {
        ScrollView {
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

                Toggle(isOn: preferKnownStepsBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prefer known steps (reuse recorded skills, less screen-reading)")
                        Text("Instructs the agent to replay compiled/recorded skills when available.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .toggleStyle(.switch)

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

                Divider()
                permissionsSection

                if let message = settings.statusMessage {
                    Text(message).font(.caption).foregroundStyle(Theme.err)
                }
            }
            .padding(Theme.s6)
        }
        .frame(width: 520, height: 700)
        .background(Theme.surface)
        .task { await pollPermissionStatus() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )) { _ in
            refreshPermissionStatus()
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("Permissions")
                .font(.headline)
                .foregroundStyle(Theme.text)

            permissionRow(
                title: "Accessibility",
                granted: accessibilityGranted,
                request: SystemPermissions.requestAccessibility,
                openSettings: SystemPermissions.openAccessibilitySettings
            )
            Text("Used only to position and dock mirror windows.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            permissionRow(
                title: "Screen Recording",
                granted: screenRecordingGranted,
                request: SystemPermissions.requestScreenRecording,
                openSettings: SystemPermissions.openScreenRecordingSettings
            )
            Text("Captures only the iPhone Mirroring window (iOS) or the device's own "
                 + "screen via adb (Android). The Mac screen is never recorded.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            field("Screen capture policy") {
                Picker("Screen capture policy", selection: screenCapturePolicyBinding) {
                    ForEach(ScreenCapturePolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(settings.screenCapturePolicy.description)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Label(
                    granted ? "Granted" : "Not Granted",
                    systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(granted ? Theme.ok : Theme.err)
            }
            HStack {
                Button("Request…") {
                    request()
                    refreshPermissionStatus()
                }
                Button("Open System Settings", action: openSettings)
            }
        }
        .padding(Theme.s3)
        .cardSurface(elevated: true)
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

    private var preferKnownStepsBinding: Binding<Bool> {
        Binding(
            get: { settings.preferKnownSteps },
            set: { settings.setPreferKnownSteps($0) }
        )
    }

    private var screenCapturePolicyBinding: Binding<ScreenCapturePolicy> {
        Binding(
            get: { settings.screenCapturePolicy },
            set: { settings.setScreenCapturePolicy($0) }
        )
    }

    private func saveKey() {
        if settings.saveKey(keyEntry, for: backend) { keyEntry = "" }
    }

    private func refreshPermissionStatus() {
        accessibilityGranted = SystemPermissions.accessibilityGranted
        screenRecordingGranted = SystemPermissions.screenRecordingGranted
    }

    private func pollPermissionStatus() async {
        refreshPermissionStatus()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            refreshPermissionStatus()
        }
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
