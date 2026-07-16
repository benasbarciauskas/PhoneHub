import PhoneHubCore
import SwiftUI

struct BuilderTimelineRow: View {
    let step: AutomationStep
    let index: Int
    @Bindable var draftStore: BuilderDraftStore
    @Bindable var textSourceStore: TextSourceStore
    let editTap: (AutomationStep) -> Void
    let insert: (BuilderInsertKind, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: automationStepIcon(step))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(index + 1). \(automationStepTitle(step))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Menu("Insert before") { insertButtons(at: index) }
                    Menu("Insert after") { insertButtons(at: index + 1) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Insert after this action")
                Button(role: .destructive) {
                    draftStore.delete(at: IndexSet(integer: index))
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            editableFields
        }
        .padding(.vertical, Theme.s1)
    }

    @ViewBuilder
    private func insertButtons(at position: Int) -> some View {
        Button("Pause") { insert(.pause, position) }
        Button("Type text") { insert(.typeText, position) }
        Button("AI action") { insert(.aiAction, position) }
    }

    private var summary: String {
        if case .typeText = step,
           let sourceID = draftStore.draft.textSourceBindings[step.id]?.sourceID,
           let source = textSourceStore.sources.first(where: { $0.id == sourceID }) {
            return "Source: \(source.name) · \(source.currentItem ?? "No item")"
        }
        return automationStepSummary(step)
    }

    @ViewBuilder
    private var editableFields: some View {
        switch step {
        case let .wait(id, milliseconds):
            HStack {
                TextField("Milliseconds", value: Binding(
                    get: { milliseconds },
                    set: { draftStore.update(.wait(id: id, ms: min(max($0, 0), 3_600_000))) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                Stepper("", value: Binding(
                    get: { milliseconds },
                    set: { draftStore.update(.wait(id: id, ms: $0)) }
                ), in: 0...3_600_000, step: 100)
                .labelsHidden()
            }
        case let .typeText(id, text):
            typeTextFields(id: id, text: text)
        case let .aiStep(id, prompt):
            TextField("Action to resolve at run time", text: Binding(
                get: { prompt },
                set: { draftStore.update(.aiStep(id: id, prompt: $0)) }
            ), axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
        case .tap, .doubleTap, .longPress:
            Button("Edit target…") { editTap(step) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.system(size: 11, weight: .medium))
        default:
            EmptyView()
        }
    }

    private func typeTextFields(id: UUID, text: String) -> some View {
        let selected = draftStore.draft.textSourceBindings[id]?.sourceID
        return VStack(alignment: .leading, spacing: Theme.s1) {
            Picker("Text", selection: Binding<UUID?>(
                get: { selected },
                set: { draftStore.setTextSource($0, forStepID: id) }
            )) {
                Text("Literal text").tag(UUID?.none)
                ForEach(textSourceStore.sources) { source in
                    Text(source.name).tag(Optional(source.id))
                }
                if let selected,
                   !textSourceStore.sources.contains(where: { $0.id == selected }) {
                    Text("Missing source").tag(Optional(selected))
                }
            }
            .labelsHidden()
            TextField("Text to type", text: Binding(
                get: { text },
                set: { draftStore.update(.typeText(id: id, text: $0)) }
            ), axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .disabled(selected != nil)
        }
    }
}

enum BuilderInsertKind {
    case pause
    case typeText
    case aiAction
}
