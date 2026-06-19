import Foundation
import Observation
import PhoneHubCore

@Observable
@MainActor
final class DeviceStore {
    var devices: [Device] = []
    var focusedID: Device.ID?
    var toolMissing = false

    var focused: Device? { devices.first { $0.id == focusedID } }

    /// Re-run discovery off the main actor, then publish.
    func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = AndroidController.discover()       // Android only for this slice
            let missing = resolveTool("adb") == nil
            await MainActor.run {
                self.toolMissing = missing
                self.devices = found
                if self.focusedID == nil { self.focusedID = found.first?.id }
                else if !found.contains(where: { $0.id == self.focusedID }) {
                    self.focusedID = found.first?.id
                }
            }
        }
    }

    func focus(_ id: Device.ID) { focusedID = id }
}
