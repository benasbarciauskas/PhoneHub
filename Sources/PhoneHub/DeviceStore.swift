import Foundation
import Observation
import PhoneHubCore

enum StageLayout: String, CaseIterable, Identifiable {
    case focus
    case wall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .wall: return "Wall"
        }
    }
}

@Observable
@MainActor
final class DeviceStore {
    var devices: [Device] = []
    var focusedDevice: Device?
    var layout: StageLayout = .focus
    var toolMissing = false

    /// Re-run discovery off the main actor, then publish.
    func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = AndroidController.discover() + IOSController.discover()
            let missing = resolveTool("adb") == nil
            await MainActor.run {
                self.toolMissing = missing
                self.devices = found
                if let focused = self.focusedDevice,
                   let updated = found.first(where: { $0.id == focused.id }) {
                    self.focusedDevice = updated
                } else {
                    self.focusedDevice = found.first
                }
            }
        }
    }

    func setFocused(_ device: Device) {
        focusedDevice = device
    }
}
