import SwiftUI
import PhoneHubCore

struct ManualTapPicker: View {
    @Environment(\.dismiss) private var dismiss

    let device: Device
    let existingStep: AutomationStep?
    let confirm: (AutomationStep) -> Void

    @State private var model = ManualTapPickerModel()
    @State private var clickInView: CGPoint?
    @State private var imageViewSize = CGSize.zero
    @State private var label = ""

    var body: some View {
        VStack(spacing: Theme.s3) {
            Text("Click where you want to tap")
                .font(.headline)
                .foregroundStyle(Theme.text)

            screenshotArea

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.err)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.s2) {
                TextField("Optional target label", text: $label)
                    .textFieldStyle(.roundedBorder)
                Button("Retake") {
                    clickInView = nil
                    Task { await model.load(device: device) }
                }
                .disabled(model.isLoading)
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Confirm") { confirmSelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(clickInView == nil || model.image == nil)
            }
        }
        .padding(Theme.s4)
        .frame(width: 620, height: 760)
        .background(Theme.surface)
        .task {
            label = existingLabel
            await model.load(device: device)
        }
        .onDisappear { model.stop() }
    }

    private var screenshotArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = model.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.85)
                    Color.black.opacity(0.12)
                    if let clickInView {
                        Circle()
                            .stroke(Theme.accent, lineWidth: 3)
                            .background(Circle().fill(Color.black.opacity(0.25)))
                            .frame(width: 26, height: 26)
                            .position(clickInView)
                        Path { path in
                            path.move(to: CGPoint(x: clickInView.x - 18, y: clickInView.y))
                            path.addLine(to: CGPoint(x: clickInView.x + 18, y: clickInView.y))
                            path.move(to: CGPoint(x: clickInView.x, y: clickInView.y - 18))
                            path.addLine(to: CGPoint(x: clickInView.x, y: clickInView.y + 18))
                        }
                        .stroke(Theme.accent, lineWidth: 1)
                    }
                } else if model.isLoading {
                    ProgressView("Fetching current screenshot…")
                        .foregroundStyle(Theme.text)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                guard model.image != nil else { return }
                clickInView = event.location
            })
            .onAppear { imageViewSize = geometry.size }
            .onChange(of: geometry.size) { _, size in imageViewSize = size }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMd).stroke(Theme.border))
    }

    private var existingLabel: String {
        switch existingStep {
        case let .tap(_, label, _, _), let .doubleTap(_, label, _, _),
             let .longPress(_, label, _, _, _): return label ?? ""
        default: return ""
        }
    }

    private func confirmSelection() {
        guard let clickInView else { return }
        let point = mapClickToDevicePoint(
            clickInView: clickInView,
            viewSize: imageViewSize,
            imagePixelSize: model.imagePixelSize,
            deviceSpaceSize: model.deviceSpaceSize
        )
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionalLabel = cleanLabel.isEmpty ? nil : cleanLabel
        let step: AutomationStep
        switch existingStep {
        case let .doubleTap(id, _, _, _):
            step = .doubleTap(id: id, label: optionalLabel, x: point.x, y: point.y)
        case let .longPress(id, _, _, _, duration):
            step = .longPress(id: id, label: optionalLabel, x: point.x, y: point.y,
                              durationMs: duration)
        case let .tap(id, _, _, _):
            step = .tap(id: id, label: optionalLabel, x: point.x, y: point.y)
        default:
            step = .tap(id: UUID(), label: optionalLabel, x: point.x, y: point.y)
        }
        confirm(step)
        dismiss()
    }
}
