// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseWheelFix",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseWheelFix", targets: ["MouseWheelFix"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "ScrollCore"),
        .target(name: "AppLocalization", resources: [.process("Resources")]),
        .target(name: "FolderCore", dependencies: ["AppLocalization"]),
        .target(name: "PowerCore", dependencies: ["AppLocalization"]),
        .executableTarget(
            name: "MouseWheelFix",
            dependencies: ["ScrollCore", "FolderCore", "PowerCore", "AppLocalization", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AppLocalizationTests", dependencies: ["AppLocalization"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
        .testTarget(name: "FolderCoreTests", dependencies: ["FolderCore"]),
        .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"])
    ]
)
