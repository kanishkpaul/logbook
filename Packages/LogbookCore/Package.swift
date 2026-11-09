// swift-tools-version: 6.2
import PackageDescription

// Pure domain logic: types, interval maths, day attribution.
// Nonisolated by default (no MainActor), no third-party dependencies.
let package = Package(
    name: "LogbookCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogbookCore", targets: ["LogbookCore"]),
    ],
    targets: [
        .target(
            name: "LogbookCore",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "LogbookCoreTests",
            dependencies: ["LogbookCore"]
        ),
    ]
)
