// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MussolFeiner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MussolFeinerCore", targets: ["MussolFeinerCore"]),
        .executable(name: "mussol-feiner", targets: ["MussolFeiner"])
    ],
    targets: [
        .target(
            name: "MussolFeinerCore"
        ),
        .executableTarget(
            name: "MussolFeiner",
            dependencies: ["MussolFeinerCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "MussolFeinerCoreTests",
            dependencies: ["MussolFeinerCore"]
        )
    ]
)
