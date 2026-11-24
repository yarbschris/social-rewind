// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewindCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RewindCore", targets: ["RewindCore"]),
    ],
    targets: [
        .target(name: "RewindCore"),
        .testTarget(name: "RewindCoreTests", dependencies: ["RewindCore"]),
    ]
)
