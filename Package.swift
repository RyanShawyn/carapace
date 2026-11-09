// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "carapace",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "carapace", targets: ["Carapace"]),
        .executable(name: "carapace-cli", targets: ["CarapaceCLI"])
    ],
    targets: [
        .target(
            name: "CarapaceCore",
            path: "Sources/CarapaceCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Carapace",
            dependencies: ["CarapaceCore"],
            path: "Sources/Carapace",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CarapaceCLI",
            dependencies: ["CarapaceCore"],
            path: "Sources/CarapaceCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CarapaceCoreTests",
            dependencies: ["CarapaceCore"],
            path: "Tests/CarapaceCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
