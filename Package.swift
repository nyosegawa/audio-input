// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioInput",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "AudioInput",
            dependencies: ["WhisperKit"],
            path: "Sources/AudioInput",
            resources: [.copy("Resources")]
        ),
    ]
)
