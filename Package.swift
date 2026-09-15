// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LilButterfly",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "LilButterfly",
            path: "Sources/LilButterfly",
            resources: [
                .copy("Resources/Wings")
            ]
        )
    ]
)
