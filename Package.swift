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
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", exact: "0.63.2")
    ],
    targets: [
        .target(
            name: "Iris",
            exclude: ["Excluded"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "IrisTests",
            dependencies: ["Iris"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
    ]
)
