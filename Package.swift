// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "SocketIO",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)],
    products: [.library(name: "SocketIO", targets: ["SocketIO"])],
    dependencies: [],
    targets: [
        .target(name: "SocketIO", dependencies: [], path: "Source/SocketIO"),
        .testTarget(name: "TestSocketIO", dependencies: ["SocketIO"]),
    ]
)
