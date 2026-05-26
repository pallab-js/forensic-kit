// swift-tools-version: 5.9
// SPEC: REQ-000 — Package manifest defining ForensicKit multi-target SPM project

import PackageDescription

let package = Package(
    name: "ForensicKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Executable CLI tool
        .executable(
            name: "forensic-kit",
            targets: ["ForensicKitCLI"]
        ),
        // Library target (importable by external packages / tests)
        .library(
            name: "ForensicKit",
            targets: ["ForensicKit"]
        )
    ],
    dependencies: [
        // swift-argument-parser for CLI (Phase 5)
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
        // swift-testing: working test framework on this toolchain (macOS 26 beta)
        // XCTest module is unavailable in CLI mode on this pre-release SDK.
        .package(
            url: "https://github.com/apple/swift-testing",
            from: "0.10.0"
        )
    ],
    targets: [
        // Core library — all forensic logic lives here
        .target(
            name: "ForensicKit",
            dependencies: [],
            path: "Sources/ForensicKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // CLI executable — thin wrapper over ForensicKit (Phase 5)
        .executableTarget(
            name: "ForensicKitCLI",
            dependencies: [
                "ForensicKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ForensicKitCLI"
        ),
        // Test suite — Swift Testing (@Test) via swift-testing package
        // XCTest unavailable in CLI mode on macOS 26 beta toolchain.
        .testTarget(
            name: "ForensicKitTests",
            dependencies: [
                "ForensicKit",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/ForensicKitTests",
            swiftSettings: [
                // Suppress deprecation warning: swift-testing required by SPM
                // for test discovery even though Swift 6 bundles Testing natively.
                .unsafeFlags(["-suppress-warnings"])
            ]
        )
    ]
)
