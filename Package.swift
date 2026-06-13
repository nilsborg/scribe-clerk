// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceMemoTranscriber",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceMemoTranscriber",
            path: "Sources/VoiceMemoTranscriber"
        )
    ]
)
