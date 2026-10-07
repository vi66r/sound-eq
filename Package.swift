// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundEQ",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "SoundEQ", targets: ["SoundEQ"]),
        .library(name: "AudioCore", targets: ["AudioCore"])
    ],
    targets: [
        .target(name: "AudioRing"),
        .target(name: "AudioCore", dependencies: ["AudioRing"]),
        .executableTarget(name: "SoundEQ", dependencies: ["AudioCore"]),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore", "AudioRing"])
    ],
    swiftLanguageModes: [.v5]
)
