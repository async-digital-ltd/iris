// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iris",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Iris",
            targets: ["Iris"]
        )
    ],
    targets: [
        .target(
            name: "Iris",
            exclude: ["Excluded"]
        ),
        .testTarget(
            name: "IrisTests",
            dependencies: ["Iris"]
        )
    ]
)
