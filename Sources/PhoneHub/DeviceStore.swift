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
    var wallGridPreset: WallGridPreset = .auto
    var wallTileOrder: [String: Int] = [:]
    var wallZoomByDeviceID: [String: CGFloat] = [:]
    var toolMissing = false
    private var removedDeviceIDs: Set<String> = []
    private var customNames: [String: String] = [:]
    private let namesFileURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? PresetStore.defaultDirectory()
        namesFileURL = directory.appendingPathComponent("device-names.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: namesFileURL),
           let names = try? JSONDecoder().decode([String: String].self, from: data) {
            customNames = names
        }
    }

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

    /// Connect an Android device over the network (`adb connect host:port`), then refresh discovery.
    /// Persists nothing extra — discovery picks up the adb session.
    func connectAndroid(hostPort: String) async -> Result<String, AndroidConnectError> {
        let result = await Task.detached(priority: .userInitiated) {
            AndroidController.connect(hostPort: hostPort)
        }.value

        if case .success = result {
            let found = await Task.detached(priority: .userInitiated) {
                AndroidController.discover() + IOSController.discover()
            }.value
            toolMissing = resolveTool("adb") == nil
            applyDiscovery(found)
        }
        return result
    }

    func remove(deviceId: String) {
        removedDeviceIDs.insert(deviceId)
        devices.removeAll { $0.id == deviceId }
        if focusedDevice?.id == deviceId {
            focusedDevice = devices.first
        }
    }

    func setName(deviceId: String, name: String?) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            customNames.removeValue(forKey: deviceId)
        } else {
            customNames[deviceId] = trimmedName
        }
        saveCustomNames()
    }

    func displayName(for device: Device) -> String {
        customNames[device.id] ?? device.model
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

    private func saveCustomNames() {
        guard let data = try? JSONEncoder().encode(customNames) else { return }
        try? data.write(to: namesFileURL, options: .atomic)
    }
}
