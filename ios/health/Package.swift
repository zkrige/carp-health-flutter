// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "health",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "health", targets: ["health"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "health",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        )
    ]
)
