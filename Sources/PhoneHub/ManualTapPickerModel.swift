import AppKit
import Foundation
import ImageIO
import Observation
import PhoneHubCore

enum ManualTapPickerError: Error, LocalizedError {
    case screenshot(String)
    case missingImage
    case invalidImage
    case missingDeviceSpace

    var errorDescription: String? {
        switch self {
        case .screenshot(let message):
            return message.isEmpty ? "The phone screenshot failed." : message
        case .missingImage: return "The phone did not return a screenshot."
        case .invalidImage: return "The phone returned an unreadable screenshot."
        case .missingDeviceSpace:
            return "Could not determine the current iPhone Mirroring coordinate space."
        }
    }
}

@Observable
@MainActor
final class ManualTapPickerModel {
    private(set) var image: NSImage?
    private(set) var imagePixelSize = CGSize.zero
    private(set) var deviceSpaceSize = CGSize.zero
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var client: McpDirectClient?

    func load(device: Device) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let connection: McpDirectClient
            if let client {
                connection = client
            } else {
                connection = makePhoneMcpClient(for: device.platform)
                try await connection.start()
                client = connection
            }

            let arguments = directMcpArguments(for: device)
            let screenshot = try await connection.callTool(
                "screenshot", arguments: arguments, timeoutSeconds: 20
            )
            guard !screenshot.isError else {
                throw ManualTapPickerError.screenshot(screenshot.text)
            }
            guard let encoded = screenshot.imageBase64,
                  let data = Data(base64Encoded: encoded) else {
                throw ManualTapPickerError.missingImage
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  let decoded = NSImage(data: data) else {
                throw ManualTapPickerError.invalidImage
            }

            let pixels = CGSize(width: width.doubleValue, height: height.doubleValue)
            let deviceSpace: CGSize
            if device.platform == .android {
                // Androir screenshot and input tools both use physical device pixels.
                deviceSpace = pixels
            } else {
                // Mirroir screenshot images are backing pixels, while both tap and
                // describe_screen use the current mirroring-window point space.
                // Its status tool is the runtime source of that authoritative size.
                let status = try await connection.callTool(
                    "status", arguments: [:], timeoutSeconds: 10
                )
                guard !status.isError, let size = parseMirroirWindowSize(status.text) else {
                    throw ManualTapPickerError.missingDeviceSpace
                }
                deviceSpace = size
            }

            image = decoded
            imagePixelSize = pixels
            deviceSpaceSize = deviceSpace
        } catch {
            errorMessage = error.localizedDescription
            if image == nil { stop() }
        }
    }

    func stop() {
        client?.stop()
        client = nil
    }
}
