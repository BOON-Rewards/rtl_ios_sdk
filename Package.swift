// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RTLSdk",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RTLSdk",
            targets: ["RTLSdk"]
        )
    ],
    targets: [
        .target(
            name: "RTLSdk",
            path: "Sources/RTLSdk",
            resources: [
                .process("LICENSE.md")
            ]
        ),
        .testTarget(
            name: "RTLSdkTests",
            dependencies: ["RTLSdk"],
            path: "Tests/RTLSdkTests"
        )
    ]
)
