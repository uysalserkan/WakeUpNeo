// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required.
// Update .macOS(.v15) to .macOS(.v26) once Xcode 26 SDK ships.

import PackageDescription

let package = Package(
    name: "WakeUpNeo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "WakeUpNeo", targets: ["WakeUpNeo"])
    ],
    targets: [
        // MARK: WakeUpNeoCore — all testable business logic (no SwiftUI dependency)
        .target(
            name: "WakeUpNeoCore",
            path: "Sources/WakeUpNeoCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),

        // MARK: WakeUpNeo — thin SwiftUI app shell, depends on WakeUpNeoCore
        .executableTarget(
            name: "WakeUpNeo",
            dependencies: ["WakeUpNeoCore"],
            path: "Sources/WakeUpNeo",
            resources: [
                .process("Resources")
            ]
        ),

        // MARK: WakeUpNeoTests — unit tests against WakeUpNeoCore only
        .testTarget(
            name: "WakeUpNeoTests",
            dependencies: ["WakeUpNeoCore"],
            path: "Tests/WakeUpNeoTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
