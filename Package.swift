// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketType",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PocketType", targets: ["Drift"])],
    targets: [
        .target(name: "WebKitBackground"),
        .executableTarget(name: "Drift", dependencies: ["WebKitBackground"], resources: [.process("Resources")]),
        .testTarget(name: "DriftTests", dependencies: ["Drift"]),
    ]
)
