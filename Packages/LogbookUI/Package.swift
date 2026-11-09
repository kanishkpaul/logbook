// swift-tools-version: 6.2
import PackageDescription

// Design system and feature views. MainActor default isolation + Approachable
// Concurrency. Every view has a #Preview.
let package = Package(
    name: "LogbookUI",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogbookUI", targets: ["LogbookUI"]),
    ],
    dependencies: [
        .package(path: "../LogbookCore"),
    ],
    targets: [
        .target(
            name: "LogbookUI",
            dependencies: ["LogbookCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
