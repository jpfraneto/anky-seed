// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnkyIOS",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AnkyProtocol", targets: ["AnkyProtocol"]),
        .library(name: "AnkyCore", targets: ["AnkyCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/web3swift-team/web3swift.git", from: "3.3.2")
    ],
    targets: [
        .target(
            name: "AnkyProtocol",
            path: "Anky/Core/Protocol"
        ),
        .target(
            name: "AnkyCore",
            dependencies: [
                "AnkyProtocol",
                .product(name: "web3swift", package: "web3swift")
            ],
            path: "Anky/Core",
            exclude: [
                "Clipboard",
                "Protocol",
                "WriteBeforeScroll/SCREEN_TIME_SPIKE_NOTES.md"
            ]
        ),
        .testTarget(
            name: "AnkyProtocolTests",
            dependencies: ["AnkyProtocol", "AnkyCore"],
            path: "Anky/Tests",
            // These exercise the full application module and belong to the
            // Xcode test target. SwiftPM intentionally covers the portable
            // protocol/core surface only.
            exclude: [
                "DraftRecoveryTests.swift",
                "JourneyAnchorTests.swift",
                "QuoteSanitizerTests.swift",
                "SubscriptionRemediationTests.swift"
            ]
        )
    ]
)
