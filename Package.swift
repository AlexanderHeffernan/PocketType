// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketType",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PocketType", targets: ["Drift"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "WebKitBackground"),
        .executableTarget(name: "Drift", dependencies: ["WebKitBackground", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.process("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "DriftTests", dependencies: ["Drift"]),
    ]
)
