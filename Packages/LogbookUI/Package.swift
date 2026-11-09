// swift-tools-version: 6.2
import PackageDescription

// Design system, models and feature views. MainActor default isolation +
// Approachable Concurrency. Every view has a #Preview. Presenters are pure and
// tested; views only lay out what presenters computed.
let package = Package(
    name: "LogbookUI",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogbookUI", targets: ["LogbookUI"]),
    ],
    dependencies: [
        .package(path: "../LogbookCore"),
        .package(path: "../LogbookPersistence"),
        .package(path: "../LogbookImport"),
    ],
    targets: [
        .target(
            name: "LogbookUI",
            dependencies: ["LogbookCore", "LogbookPersistence", "LogbookImport"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "LogbookUITests",
            dependencies: ["LogbookUI", "LogbookCore", "LogbookPersistence"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
