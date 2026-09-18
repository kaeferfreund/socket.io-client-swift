// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "SocketIO",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [.library(name: "SocketIO", targets: ["SocketIO"])],
    dependencies: [],
    targets: [
        .target(name: "SocketIO", dependencies: [], path: "Source/SocketIO"),
        .testTarget(name: "TestSocketIO", dependencies: ["SocketIO"], exclude: ["E2E/Fixtures"]),
    ]
)
