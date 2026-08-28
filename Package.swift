// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mac-tool-kit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacToolKitCore",
            targets: ["MacToolKitCore"]
        ),
        .executable(
            name: "MacDashboardApp",
            targets: ["MacDashboardApp"]
        ),
        .executable(
            name: "MacDashboardFanHelper",
            targets: ["MacDashboardFanHelper"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacToolKitCore",
            dependencies: [],
            path: "Sources/MacToolKitCore"
        ),
        .executableTarget(
            name: "MacDashboardApp",
            dependencies: ["MacToolKitCore"],
            path: "Sources/MacDashboardApp"
        ),
        .executableTarget(
            name: "MacDashboardFanHelper",
            dependencies: [],
            path: "Sources/MacDashboardFanHelper"
        ),
        .testTarget(
            name: "MacToolKitCoreTests",
            dependencies: ["MacToolKitCore"],
            path: "Tests/MacToolKitCoreTests"
        )
    ]
)
