// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "device_shield",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "device-shield", targets: ["device_shield"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "device_shield",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Declares no tracking, no collected data and no required-reason APIs.
                // Keep in sync with the podspec's resource_bundles entry.
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "device_shieldTests",
            dependencies: [
                "device_shield",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
