import SwiftUI
import PhoneHubCore

/// Polls device frames (~2 fps) and forwards clicks as taps.
struct StreamView: View {
    let serial: String

    @State private var frame: NSImage?
    @State private var deviceSize: CGSize = .init(width: 1080, height: 2340)
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg
                if let frame {
                    Image(nsImage: frame)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let p = viewPointToDevicePoint(location, viewSize: geo.size, deviceSize: deviceSize)
                let serial = serial
                Task.detached { AndroidController.tap(serial: serial, x: Int(p.x), y: Int(p.y)) }
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .onChange(of: serial) { _, _ in restart() }
    }

    private func start() {
        if let s = AndroidController.screenSize(serial: serial) { deviceSize = s }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in poll() }
    }
    private func stop() { timer?.invalidate(); timer = nil }
    private func restart() { stop(); frame = nil; start() }

    private func poll() {
        let serial = serial
        Task.detached(priority: .userInitiated) {
            guard let data = AndroidController.captureFrame(serial: serial),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { self.frame = img }
        }
    }
}
