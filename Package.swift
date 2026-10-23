// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Chum",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Chum", targets: ["Chum"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0")
    ],
    targets: [
        .target(
            name: "ChumCore",
            path: "Sources/ChumCore"
        ),
        .executableTarget(
            name: "Chum",
            dependencies: [
                "ChumCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Chum"
        ),
        .executableTarget(
            name: "ChumTests",
            dependencies: ["ChumCore"],
            path: "Tests/ChumTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
