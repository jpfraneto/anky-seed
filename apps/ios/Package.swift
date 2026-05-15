// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnkyIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AnkyProtocol", targets: ["AnkyProtocol"]),
        .library(name: "AnkyCore", targets: ["AnkyCore"])
    ],
    targets: [
        .target(
            name: "AnkyProtocol",
            path: "Anky/Core/Protocol"
        ),
        .target(
            name: "AnkyCore",
            dependencies: ["AnkyProtocol"],
            path: "Anky/Core",
            exclude: [
                "Clipboard",
                "Protocol"
            ]
        ),
        .testTarget(
            name: "AnkyProtocolTests",
            dependencies: ["AnkyProtocol", "AnkyCore"],
            path: "Anky/Tests"
        )
    ]
)
