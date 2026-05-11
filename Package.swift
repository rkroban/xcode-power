// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "XcodePower",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "XcodePower", targets: ["XcodePower"])
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.0.0")
    ],
    targets: [
        .executableTarget(
            name: "XcodePower",
            dependencies: [
                "XcodeProj"
            ],
            path: "Sources/XcodePower"
        ),
        .testTarget(
            name: "XcodePowerTests",
            dependencies: [
                "XcodePower",
                "SwiftCheck"
            ],
            path: "Tests/XcodePowerTests"
        )
    ]
)
