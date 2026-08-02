// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "XShot", targets: ["XShot"]),
        .executable(name: "XShotSmokeTests", targets: ["XShotSmokeTests"]),
        .library(name: "XShotKit", targets: ["XShotKit"])
    ],
    targets: [
        .target(
            name: "XShotKit",
            path: "Sources/XShotKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "XShot",
            dependencies: ["XShotKit"],
            path: "Sources/XShot"
        ),
        .executableTarget(
            name: "XShotSmokeTests",
            dependencies: ["XShotKit"],
            path: "Sources/XShotSmokeTests"
        ),
        .testTarget(
            name: "XShotTests",
            dependencies: ["XShotKit"],
            path: "Tests/XShotTests"
        )
    ]
)
