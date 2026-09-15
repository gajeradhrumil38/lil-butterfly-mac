// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Butterfly",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Butterfly",
            path: "Sources/LilButterfly",
            resources: [
                .copy("Resources/Wings")
            ]
        )
    ]
)
