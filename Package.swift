// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseGesture",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseGesture", targets: ["MouseGesture"])],
    targets: [
        .target(name: "GestureCore"),
        .executableTarget(name: "MouseGesture", dependencies: ["GestureCore"])
    ]
)
