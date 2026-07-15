import SwiftUI
import PhoneHubCore

struct ChatPanel: View {
    var engine: ChatEngine
    var presetEngine: AutomationEngine
    var automationBusy: Bool
    let focused: Device?
    let backend: AgentBackend

    @State private var input = ""

    var body: some View {
        VStack(spacing: Theme.s2) {
            if let focused {
                transcript
                composer(for: focused)
            } else {
                Spacer()
                Text("Focus a device to chat.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.s2)
        .padding(.bottom, Theme.s3)
        .onAppear { bindFocusedDevice() }
        .onChange(of: focused?.id) { _, _ in bindFocusedDevice() }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.s2) {
                    ForEach(engine.chat.messages) { message in
                        ChatBubble(message: message).id(message.id)
                    }
                    if !engine.streamingText.isEmpty {
                        HStack(alignment: .bottom, spacing: Theme.s2) {
                            Text(engine.streamingText)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .padding(Theme.s2)
                                .cardSurface(elevated: true)
                            ProgressView().controlSize(.mini)
                            Spacer(minLength: Theme.s4)
                        }
                        .id("streaming")
                    } else if engine.isBusy {
                        ProgressView().controlSize(.small).id("streaming")
                    }
                }
                .padding(.vertical, Theme.s2)
            }
            .onChange(of: engine.chat.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: engine.streamingText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func composer(for device: Device) -> some View {
        VStack(spacing: Theme.s2) {
            if presetEngine.isBusy || automationBusy {
                Text(automationBusy ? "Automation run active" : "Preset run active")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.subtext)
            }
            if case let .failed(message) = engine.turnState {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.err)
                    .lineLimit(2)
            }
            HStack(spacing: Theme.s2) {
                TextField("Message…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(engine.isBusy || presetEngine.isBusy || automationBusy)
                    .onSubmit { send(on: device) }

                if engine.isBusy {
                    Button("Stop") { engine.stop() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.err)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Button { send(on: device) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Theme.accent : Theme.subtext.opacity(0.4))
                    .disabled(!canSend)
                }

                Menu {
                    Button("New chat", systemImage: "square.and.pencil") {
                        engine.newChat(deviceId: device.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(Theme.subtext)
                .disabled(engine.isBusy)
            }
        }
        .padding(Theme.s2)
        .cardSurface()
    }

    private var canSend: Bool {
        !engine.isBusy
            && !presetEngine.isBusy
            && !automationBusy
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(on device: Device) {
        guard canSend else { return }
        let text = input
        if engine.send(text, on: device, backend: backend,
                       presetEngineBusy: presetEngine.isBusy || automationBusy) {
            input = ""
        }
    }

    private func bindFocusedDevice() {
        if let focused { engine.bind(device: focused) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if engine.isBusy {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let id = engine.chat.messages.last?.id {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: Theme.s4)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .padding(Theme.s2)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .padding(Theme.s2)
                    .cardSurface(elevated: true)
                Spacer(minLength: Theme.s4)
            }
        case .tool:
            Text(message.text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            Text(message.text)
                .font(.system(size: 10).italic())
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
