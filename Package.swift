// swift-tools-version: 6.2
import PackageDescription

// HudEX — a tiny, always-present, almost-invisible display of recent
// research-project context that lives in the free space next to the Dock.
//
// Two targets only:
//   HudEXCore — pure Swift (Foundation), no AppKit UI.
//   HudEXApp  — SwiftUI/AppKit shell: edge panels, settings, menu bar.
let package = Package(
    name: "HudEX",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "HudEXCore", targets: ["HudEXCore"]),
        .executable(name: "HudEX", targets: ["HudEXApp"])
    ],
    targets: [
        .target(
            name: "HudEXCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "HudEXApp",
            dependencies: ["HudEXCore"]
        ),
        .testTarget(
            name: "HudEXCoreTests",
            dependencies: ["HudEXCore"]
        )
    ],
    // The sources are written against Swift 5 semantics; pinning the language
    // mode keeps the manifest/SDK version independent from a Swift 6
    // concurrency migration.
    swiftLanguageModes: [.v5]
)
