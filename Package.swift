// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Workbench",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Workbench",
            path: "Sources/Workbench"
        )
    ]
)
