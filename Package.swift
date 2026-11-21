// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pomodoraaa",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pomodoraaa",
            path: "Sources/Pomodoraaa"
        )
    ]
)
