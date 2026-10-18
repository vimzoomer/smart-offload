// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "smart-offload",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OffloadCore", targets: ["OffloadCore"]),
        .executable(name: "offload-worker", targets: ["OffloadWorker"]),
    ],
    targets: [
        .target(name: "OffloadCore"),
        .executableTarget(name: "OffloadWorker", dependencies: ["OffloadCore"]),
        .testTarget(name: "OffloadCoreTests", dependencies: ["OffloadCore"]),
    ]
)
