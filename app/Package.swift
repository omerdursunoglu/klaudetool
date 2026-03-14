// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "KlaudeTool",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KlaudeTool",
            path: "Sources/KlaudeTool"
        )
    ]
)
