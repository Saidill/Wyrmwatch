// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wyrmwatch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // The mascot's animations (played only when Resources/wyrm.riv is present).
        .package(url: "https://github.com/rive-app/rive-ios", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Wyrmwatch",
            dependencies: [.product(name: "RiveRuntime", package: "rive-ios")],
            path: "Sources/Wyrmwatch"
        )
    ]
)
