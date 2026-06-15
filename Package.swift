// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScribeClerk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScribeClerk",
            path: "Sources/ScribeClerk"
        )
    ]
)
