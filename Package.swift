// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PhoneHubCore"),
        .executableTarget(
            name: "PhoneHub",
            dependencies: ["PhoneHubCore"]
        ),
        .testTarget(
            name: "PhoneHubCoreTests",
            dependencies: ["PhoneHubCore"],
            exclude: ["Fixtures/stream-sample.ndjson"]
        ),
        .testTarget(
            name: "PhoneHubTests",
            dependencies: ["PhoneHub"]
        ),
    ]
)
