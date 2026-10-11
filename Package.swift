// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hoop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Hoop", path: "Sources/Hoop"),
    ]
)
