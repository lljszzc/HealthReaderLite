// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthReaderLite",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "HealthReaderLite",
            path: "Sources/HealthReaderLite",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)