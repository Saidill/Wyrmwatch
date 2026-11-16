// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wyrmwatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Wyrmwatch",
            path: "Sources/Wyrmwatch"
        )
    ]
)
