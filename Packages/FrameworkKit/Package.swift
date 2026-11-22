// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrameworkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FrameworkKit", targets: ["FrameworkKit"]),
        .library(name: "DesignTokens", targets: ["DesignTokens"]),
    ],
    targets: [
        .target(name: "FrameworkKit"),
        .target(name: "DesignTokens"),
        .testTarget(name: "FrameworkKitTests", dependencies: ["FrameworkKit"]),
        .testTarget(name: "DesignTokensTests", dependencies: ["DesignTokens"]),
    ]
)
