import SwiftUI
import PhoneHubCore

struct CommunityShareItem: Identifiable {
    let id: String
    let name: String
    let app: String
    let steps: [AutomationStep]

    init(preset: Preset) {
        id = "preset-\(preset.id.uuidString)"
        name = preset.name
        app = preset.app ?? ""
        steps = [.aiStep(id: UUID(), prompt: preset.goal)]
    }

    init(automation: Automation) {
        id = "automation-\(automation.id.uuidString)"
        name = automation.name
        app = ""
        steps = automation.steps
    }
}

struct CommunityShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: CommunityShareItem
    @State private var name: String
    @State private var platform: Platform = .ios
    @State private var app: String
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var pullRequestURL: URL?

    init(item: CommunityShareItem) {
        self.item = item
        _name = State(initialValue: item.name)
        _app = State(initialValue: item.app)
    }

    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanApp: String {
        app.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if cleanName.isEmpty { errors.append("Preset name is required.") }
        if cleanApp.isEmpty { errors.append("App name is required.") }

        do {
            _ = try communityPresetJSON(
                name: cleanName.isEmpty ? "Preset" : cleanName,
                platform: platform,
                app: cleanApp.isEmpty ? "App" : cleanApp,
                steps: item.steps
            )
        } catch {
            errors.append(error.localizedDescription)
        }

        if !cleanName.isEmpty, !cleanApp.isEmpty {
            do {
                _ = try communityPresetPath(platform: platform, app: cleanApp, name: cleanName)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return Array(Set(errors)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            if let pullRequestURL {
                successView(pullRequestURL)
            } else {
                formView
            }
        }
        .padding(Theme.s4)
        .frame(width: 360, height: 580)
        .background(Theme.surface)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Share to Community").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.subtext)
                    .disabled(isSubmitting)
            }

            field("Preset name") {
                TextField("Open Instagram", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSubmitting)
            }
            field("Platform") {
                Picker("Platform", selection: $platform) {
                    Text("iOS").tag(Platform.ios)
                    Text("Android").tag(Platform.android)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(isSubmitting)
            }
            field("App name") {
                TextField("Instagram", text: $app)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSubmitting)
            }

            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("Mapped steps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.subtext)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.s2) {
                        ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
                            HStack(alignment: .top, spacing: Theme.s2) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.subtext)
                                    .frame(width: 18, alignment: .trailing)
                                Text(stepSummary(step))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(Theme.s2)
                }
                .frame(maxHeight: 180)
                .cardSurface(elevated: true)
            }

            Label(
                "Community actions are labels-only. IDs and screen coordinates are never shared.",
                systemImage: "info.circle"
            )
            .font(.system(size: 10))
            .foregroundStyle(Theme.subtext)
            .fixedSize(horizontal: false, vertical: true)

            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(validationErrors, id: \.self) { message in
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.err)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let submissionError {
                Text(submissionError)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.err)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)
                Button(action: submit) {
                    if isSubmitting {
                        HStack(spacing: Theme.s1) {
                            ProgressView().controlSize(.small)
                            Text("Submitting…")
                        }
                    } else {
                        Text("Submit")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !validationErrors.isEmpty)
            }
        }
    }

    private func successView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                Text("Pull request opened").font(.headline).foregroundStyle(Theme.text)
            }
            Text("Your preset was submitted to the PhoneHub community catalog for review.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: url) {
                HStack(spacing: Theme.s1) {
                    Text(url.absoluteString)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.right.square")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.accent)
            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func submit() {
        submissionError = nil
        let data: Data
        let path: String
        do {
            data = try communityPresetJSON(
                name: cleanName, platform: platform, app: cleanApp, steps: item.steps
            )
            path = try communityPresetPath(platform: platform, app: cleanApp, name: cleanName)
        } catch {
            submissionError = error.localizedDescription
            return
        }

        isSubmitting = true
        Task {
            do {
                pullRequestURL = try await CommunityShareController().submit(
                    json: data,
                    path: path,
                    name: cleanName,
                    platform: platform,
                    app: cleanApp
                )
            } catch {
                submissionError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.subtext)
            content()
        }
    }
}

private func stepSummary(_ step: AutomationStep) -> String {
    switch step {
    case let .launchApp(_, name): return "Launch app · \(name)"
    case let .tap(_, label, _, _): return pointSummary("Tap", label: label)
    case let .doubleTap(_, label, _, _): return pointSummary("Double tap", label: label)
    case let .longPress(_, label, _, _, durationMs):
        return "\(pointSummary("Long press", label: label)) · \(durationMs) ms"
    case let .typeText(_, text): return "Type text · \(text)"
    case let .pressKey(_, key): return "Press key · \(key)"
    case let .swipe(_, direction): return "Swipe · \(direction)"
    case .pressHome: return "Press Home"
    case .pressBack: return "Press Back"
    case .pressAppSwitcher: return "Press App Switcher"
    case let .scrollTo(_, text, direction): return "Scroll \(direction) to · \(text)"
    case let .openURL(_, url): return "Open URL · \(url)"
    case let .wait(_, ms): return "Wait · \(ms) ms"
    case let .aiStep(_, prompt): return "AI step · \(prompt)"
    case let .switchDevice(_, deviceRef): return "Switch device · \(deviceRef) (not shareable)"
    }
}

private func pointSummary(_ action: String, label: String?) -> String {
    guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "\(action) · missing label (not shareable)"
    }
    return "\(action) · \(label)"
}
