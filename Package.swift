// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockCue",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeskHUDCore", targets: ["DeskHUDCore"]),
        .executable(name: "DockCue", targets: ["DeskHUDApp"]),
        .executable(name: "deskhudctl", targets: ["deskhudctl"])
    ],
    targets: [
        .target(name: "DeskHUDCore"),
        .executableTarget(
            name: "DeskHUDApp",
            dependencies: ["DeskHUDCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "deskhudctl",
            dependencies: ["DeskHUDCore"]
        ),
        .testTarget(
            name: "DeskHUDCoreTests",
            dependencies: ["DeskHUDCore"]
        )
    ]
)
