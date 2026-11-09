// swift-tools-version: 6.2
import PackageDescription

// Schema, migrations, records, queries and the daily_facts view.
// Nonisolated by default. GRDB + SQLiteData pinned to the next minor.
let package = Package(
    name: "LogbookPersistence",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogbookPersistence", targets: ["LogbookPersistence"]),
    ],
    dependencies: [
        .package(path: "../LogbookCore"),
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.12.0")),
        .package(url: "https://github.com/pointfreeco/sqlite-data", .upToNextMinor(from: "1.12.1")),
    ],
    targets: [
        .target(
            name: "LogbookPersistence",
            dependencies: [
                "LogbookCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "LogbookPersistenceTests",
            dependencies: [
                "LogbookPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
    ]
)
