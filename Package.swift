// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UsoIA",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "UsoIA", path: "Sources/UsoIA")
    ]
)
