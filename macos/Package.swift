// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AgentNotch", path: "Sources/AgentNotch")
    ]
)
