// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlogManager",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "BlogManager",
            path: "Sources/BlogManager"
        )
    ]
)
