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
    private var removedDeviceIDs: Set<String> = []

    /// Re-run discovery off the main actor, then publish.
    func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = AndroidController.discover() + IOSController.discover()
            let missing = resolveTool("adb") == nil
            await MainActor.run {
                self.toolMissing = missing
                self.applyDiscovery(found)
            }
        }
    }

    func remove(deviceId: String) {
        removedDeviceIDs.insert(deviceId)
        devices.removeAll { $0.id == deviceId }
        if focusedDevice?.id == deviceId {
            focusedDevice = devices.first
        }
    }

    func applyDiscovery(_ found: [Device]) {
        let presentRemovedIDs = Set(found.lazy
            .filter { self.removedDeviceIDs.contains($0.id) && self.isReallyPresent($0) }
            .map(\.id))
        removedDeviceIDs.subtract(presentRemovedIDs)

        let visible = found.filter { !removedDeviceIDs.contains($0.id) }
        devices = visible
        if let focused = focusedDevice,
           let updated = visible.first(where: { $0.id == focused.id }) {
            focusedDevice = updated
        } else {
            focusedDevice = visible.first
        }
    }

    func setFocused(_ device: Device) {
        focusedDevice = device
    }

    private func isReallyPresent(_ device: Device) -> Bool {
        device.platform == .android || device.status == "connected"
    }
}
