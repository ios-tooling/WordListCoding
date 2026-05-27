// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WordListCoding",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "WordListCoding", targets: ["WordListCoding"]),
    ],
    targets: [
        .target(name: "WordListCoding"),
        .testTarget(
            name: "WordListCodingTests",
            dependencies: ["WordListCoding"]
        ),
    ]
)
