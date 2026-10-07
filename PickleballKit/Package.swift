// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickleballKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PickleballKit", targets: ["PickleballKit"])
    ],
    targets: [
        .target(name: "PickleballKit"),
        .testTarget(name: "PickleballKitTests", dependencies: ["PickleballKit"])
    ]
)
