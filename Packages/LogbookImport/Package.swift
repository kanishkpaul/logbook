// swift-tools-version: 6.2
import PackageDescription

// Notes-shorthand parser, import plan (preview), apply and undo, plus the
// `logbook-import` command. Nonisolated by default.
let package = Package(
    name: "LogbookImport",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogbookImport", targets: ["LogbookImport"]),
        .executable(name: "logbook-import", targets: ["logbook-import"]),
    ],
    dependencies: [
        .package(path: "../LogbookCore"),
        .package(path: "../LogbookPersistence"),
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.12.0")),
        .package(url: "https://github.com/pointfreeco/sqlite-data", .upToNextMinor(from: "1.12.1")),
    ],
    targets: [
        .target(
            name: "LogbookImport",
            dependencies: [
                "LogbookCore",
                "LogbookPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .executableTarget(
            name: "logbook-import",
            dependencies: ["LogbookImport", "LogbookCore", "LogbookPersistence"]
        ),
        .testTarget(
            name: "LogbookImportTests",
            dependencies: ["LogbookImport", "LogbookCore", "LogbookPersistence"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
