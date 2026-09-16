// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Butterfly",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Butterfly",
            path: "Sources/LilButterfly",
            resources: [
                .copy("Resources/Wings"),
                .copy("Resources/ICON.svg")
            ]
        ),
        .testTarget(
            name: "ButterflyTests",
            dependencies: ["Butterfly"],
            path: "Tests/ButterflyTests"
        )
    ]
)
