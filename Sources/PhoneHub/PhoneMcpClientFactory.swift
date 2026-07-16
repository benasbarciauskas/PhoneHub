import Foundation
import PhoneHubCore

func makePhoneMcpClient(for platform: Platform) -> McpDirectClient {
    let packageArguments: [String]
    switch platform {
    case .ios:
        prepareMirroirConfigForSpawn(serverName: "mirroir")
        packageArguments = ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
    case .android:
        packageArguments = ["-y", "androir-mcp"]
    }
    if let npx = resolveTool("npx") {
        return McpDirectClient(command: npx, arguments: packageArguments)
    }
    return McpDirectClient(command: "/usr/bin/env", arguments: ["npx"] + packageArguments)
}

func directMcpArguments(for device: Device) -> [String: Any] {
    device.platform == .android ? ["serial": device.id] : [:]
}
