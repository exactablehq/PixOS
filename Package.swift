// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CoreSyncEngine", targets: ["CoreSyncEngine"]),
        .executable(name: "pixos", targets: ["pixos"]),
        .executable(name: "PixOSApp", targets: ["PixOSApp"]),
        .executable(name: "test-runner", targets: ["test-runner"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CoreSyncEngine",
            dependencies: [],
            path: "Sources/CoreSyncEngine"
        ),
        .executableTarget(
            name: "pixos",
            dependencies: ["CoreSyncEngine"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "PixOSApp",
            dependencies: ["CoreSyncEngine"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "test-runner",
            dependencies: ["CoreSyncEngine"],
            path: "Tests/TestRunner"
        )
    ]
)
