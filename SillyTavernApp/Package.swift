// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SillyTavernApp",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .executable(name: "SillyTavernApp", targets: ["SillyTavernApp"])
    ],
    dependencies: [
        // Add dependencies here as needed
    ],
    targets: [
        .executableTarget(
            name: "SillyTavernApp",
            dependencies: [],
            path: "Sources"
        )
    ]
)
