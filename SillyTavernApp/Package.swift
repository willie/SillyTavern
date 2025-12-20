// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SillyTavernApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
