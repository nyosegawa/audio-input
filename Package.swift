// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioInput",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AudioInput",
            path: "Sources/AudioInput",
            resources: [.copy("Resources")]
        ),
    ]
)
