// swift-tools-version: 6.0
import PackageDescription
import Foundation

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "AudioInput",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Dependencies/CWhisper",
            sources: ["Sources/shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(packageDir)/vendor/whisper/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(packageDir)/vendor/whisper/lib"]),
                .linkedLibrary("whisper"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "AudioInput",
            dependencies: ["CWhisper"],
            path: "Sources/AudioInput",
            resources: [.copy("Resources")]
        ),
    ]
)
