// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseWheelFix",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseWheelFix", targets: ["MouseWheelFix"])],
    targets: [
        .target(name: "ScrollCore"),
        .target(name: "FolderCore"),
        .target(name: "PowerCore"),
        .executableTarget(name: "MouseWheelFix", dependencies: ["ScrollCore", "FolderCore", "PowerCore"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
        .testTarget(name: "FolderCoreTests", dependencies: ["FolderCore"]),
        .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"])
    ]
)
