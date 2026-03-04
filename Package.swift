// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "VocaMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VocaMac",
            targets: ["VocaMac"]
        )
    ],
    dependencies: [
        // WhisperKit — local, on-device speech-to-text powered by CoreML
        // https://github.com/argmaxinc/WhisperKit
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.4"),
    ],
    targets: [
        // Main application target
        .executableTarget(
            name: "VocaMac",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/VocaMac",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        // Test target
        .testTarget(
            name: "VocaMacTests",
            dependencies: ["VocaMac"],
            path: "Tests/VocaMacTests"
        )
    ]
)
