import Foundation

private struct DevicectlResponse: Decodable {
    let result: DevicectlResult?
}

private struct DevicectlResult: Decodable {
    let devices: [DevicectlDevice]?
}

private struct DevicectlDevice: Decodable {
    let identifier: String?
    let deviceProperties: DevicectlDeviceProperties?
    let hardwareProperties: DevicectlHardwareProperties?
    let connectionProperties: DevicectlConnectionProperties?
}

private struct DevicectlDeviceProperties: Decodable {
    let name: String?
}

private struct DevicectlHardwareProperties: Decodable {
    let marketingName: String?
    let osVersionNumber: String?
    let platform: String?
}

private struct DevicectlConnectionProperties: Decodable {
    let tunnelState: String?
}

public func parseDevicectlDevices(_ data: Data) -> [Device] {
    guard let response = try? JSONDecoder().decode(DevicectlResponse.self, from: data) else {
        return []
    }

    return (response.result?.devices ?? []).compactMap { entry in
        guard let identifier = entry.identifier, !identifier.isEmpty else { return nil }
        guard entry.hardwareProperties?.platform == "iOS" else { return nil }

        let model = entry.hardwareProperties?.marketingName
            ?? entry.deviceProperties?.name
            ?? identifier
        let osVersion = entry.hardwareProperties?.osVersionNumber ?? ""
        let status = entry.connectionProperties?.tunnelState ?? "unknown"

        return Device(id: identifier,
                      platform: .ios,
                      model: model,
                      osVersion: osVersion,
                      status: status)
    }
}

public enum IOSController {
    /// Discover connected iOS devices via `xcrun devicectl`. Never throws.
    public static func discover() -> [Device] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let res = try? runTool("xcrun", ["devicectl", "list", "devices", "--json-output", tempURL.path]),
              res.exitCode == 0,
              let data = try? Data(contentsOf: tempURL) else { return [] }

        return parseDevicectlDevices(data)
    }
}
