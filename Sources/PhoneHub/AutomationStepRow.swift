import SwiftUI
import PhoneHubCore

struct AutomationStepRow: View {
    @Binding var step: AutomationStep
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    /// Connected device model/label refs for the switchDevice picker.
    var deviceRefs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack {
                Image(systemName: automationStepIcon(step)).foregroundStyle(Theme.accent).frame(width: 18)
                Text("\(index + 1). \(automationStepTitle(step))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: moveUp) { Image(systemName: "chevron.up") }.disabled(!canMoveUp)
                Button(action: moveDown) { Image(systemName: "chevron.down") }.disabled(!canMoveDown)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.subtext)
            fields
        }
        .padding(Theme.s3).cardSurface(elevated: true)
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case let .launchApp(id, name):
            field("App name", name) { step = .launchApp(id: id, name: $0) }
        case let .tap(id, label, x, y):
            pointFields(label: label, x: x, y: y) { label, x, y in
                step = .tap(id: id, label: label, x: x, y: y)
            }
        case let .doubleTap(id, label, x, y):
            pointFields(label: label, x: x, y: y) { label, x, y in
                step = .doubleTap(id: id, label: label, x: x, y: y)
            }
        case let .longPress(id, label, x, y, duration):
            pointFields(label: label, x: x, y: y) { label, x, y in
                step = .longPress(id: id, label: label, x: x, y: y, durationMs: duration)
            }
            field("Duration ms", String(duration)) {
                step = .longPress(id: id, label: label, x: x, y: y, durationMs: Int($0) ?? duration)
            }
        case let .typeText(id, text):
            field("Text", text) { step = .typeText(id: id, text: $0) }
        case let .pressKey(id, key):
            field("Key", key) { step = .pressKey(id: id, key: $0) }
        case let .swipe(id, direction):
            directionPicker(direction) { step = .swipe(id: id, direction: $0) }
        case .pressHome, .pressBack, .pressAppSwitcher:
            Text("No parameters").font(.system(size: 10)).foregroundStyle(Theme.subtext)
        case let .scrollTo(id, text, direction):
            field("Visible text", text) { step = .scrollTo(id: id, text: $0, direction: direction) }
            directionPicker(direction) { step = .scrollTo(id: id, text: text, direction: $0) }
        case let .openURL(id, url):
            field("URL", url) { step = .openURL(id: id, url: $0) }
        case let .wait(id, ms):
            field("Milliseconds", String(ms)) { step = .wait(id: id, ms: Int($0) ?? ms) }
        case let .aiStep(id, prompt):
            field("Prompt", prompt) { step = .aiStep(id: id, prompt: $0) }
        case let .switchDevice(id, deviceRef):
            deviceRefFields(id: id, deviceRef: deviceRef)
        }
    }

    @ViewBuilder
    private func deviceRefFields(id: UUID, deviceRef: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            if !deviceRefs.isEmpty {
                Picker("Device", selection: Binding(
                    get: { deviceRefs.contains(deviceRef) ? deviceRef : "" },
                    set: { if !$0.isEmpty { step = .switchDevice(id: id, deviceRef: $0) } }
                )) {
                    Text("Custom…").tag("")
                    ForEach(deviceRefs, id: \.self) { Text($0).tag($0) }
                }
            }
            field("Device ref (model or label)", deviceRef) {
                step = .switchDevice(id: id, deviceRef: $0)
            }
        }
    }

    private func field(_ placeholder: String, _ value: String,
                       update: @escaping (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: { value }, set: update), axis: .vertical)
            .lineLimit(1...3).textFieldStyle(.roundedBorder).font(.system(size: 11))
    }

    private func pointFields(label: String?, x: Double?, y: Double?,
                             update: @escaping (String?, Double?, Double?) -> Void) -> some View {
        VStack(spacing: Theme.s2) {
            field("Semantic label", label ?? "") { update($0.nilIfEmpty, x, y) }
            HStack {
                field("X (optional)", number(x)) { update(label, Double($0), y) }
                field("Y (optional)", number(y)) { update(label, x, Double($0)) }
            }
        }
    }

    private func directionPicker(_ direction: String,
                                 update: @escaping (String) -> Void) -> some View {
        Picker("Direction", selection: Binding(get: { direction }, set: update)) {
            ForEach(["up", "down", "left", "right"], id: \.self) { Text($0.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
