// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WordListCoding",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Core coding (BDEX + LZ4). No system dependencies.
        .library(name: "WordListCoding", targets: ["WordListCoding"]),
        // Optional: SQLite writer. Links against the system libsqlite3, so
        // consumers that only need BDEX should depend on the core product.
        .library(name: "WordListCodingSQLite", targets: ["WordListCodingSQLite"]),
    ],
    targets: [
        .target(name: "WordListCoding"),
        .target(
            name: "WordListCodingSQLite",
            dependencies: ["WordListCoding", "CSQLite3"]
        ),
        .systemLibrary(
            name: "CSQLite3",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"]),
                .apt(["libsqlite3-dev"]),
            ]
        ),
        .testTarget(
            name: "WordListCodingTests",
            dependencies: ["WordListCoding", "WordListCodingSQLite"]
        ),
    ]
)
