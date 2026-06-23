// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DDMMigrator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The engine: pure logic, no UI. Reusable / wrappable in a CLI later.
        .library(name: "DDMCore", targets: ["DDMCore"]),
        // The SwiftUI app. Depends on DDMCore.
        .executable(name: "DDMMigratorApp", targets: ["DDMMigratorApp"]),
    ],
    targets: [
        .target(
            name: "DDMCore",
            path: "Sources/DDMCore"
        ),
        .executableTarget(
            name: "DDMMigratorApp",
            dependencies: ["DDMCore"],
            path: "Sources/DDMMigratorApp"
        ),
        .testTarget(
            name: "DDMCoreTests",
            dependencies: ["DDMCore"],
            path: "Tests/DDMCoreTests"
        ),
    ]
)
