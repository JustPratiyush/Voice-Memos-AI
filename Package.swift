// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceMemosReplica",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VoiceMemosCore", targets: ["VoiceMemosCore"]),
        .executable(name: "VoiceMemosReplica", targets: ["VoiceMemosApp"])
    ],
    targets: [
        .target(name: "VoiceMemosCore"),
        .executableTarget(name: "VoiceMemosApp", dependencies: ["VoiceMemosCore"]),
        .testTarget(name: "VoiceMemosCoreTests", dependencies: ["VoiceMemosCore"])
    ],
    swiftLanguageVersions: [.v5]
)
