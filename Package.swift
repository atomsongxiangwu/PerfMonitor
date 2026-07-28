// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PerfMonitor",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "PerfMonitor",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // Xcode-beta SPM no longer injects @loader_path; without it,
            // `swift run` cannot find the adjacent Sparkle.framework.
            linkerSettings: [
                .unsafeFlags(
                    ["-Xlinker", "-rpath", "-Xlinker", "@loader_path"],
                    .when(platforms: [.macOS])
                ),
            ]
        ),
    ]
)
