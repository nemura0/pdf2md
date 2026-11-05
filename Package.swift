// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "pdf2md",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "pdf2md", targets: ["pdf2md"]),
        .executable(name: "FixtureGen", targets: ["FixtureGen"]),
        .library(name: "PDF2MDKit", targets: ["PDF2MDKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0")
    ],
    targets: [
        .target(name: "PDF2MDKit", swiftSettings: strictSettings),
        .executableTarget(
            name: "pdf2md",
            dependencies: [
                "PDF2MDKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSettings
        ),
        .executableTarget(name: "FixtureGen", swiftSettings: strictSettings),
        .testTarget(
            name: "PDF2MDKitTests",
            dependencies: ["PDF2MDKit", "FixtureGen", "pdf2md"],
            resources: [.copy("Golden")],
            swiftSettings: strictSettings
        ),
    ]
)
