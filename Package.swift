// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vault",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"]),
        .library(name: "VaultUI", targets: ["VaultUI"]),
    ],
    targets: [
        .target(name: "VaultCore", path: "Sources/VaultCore"),
        .target(name: "VaultUI", dependencies: ["VaultCore"], path: "Sources/VaultUI", resources: [.copy("Resources/Fonts")]),
        .executableTarget(name: "VaultPreview", dependencies: ["VaultUI", "VaultCore"], path: "Sources/VaultPreview"),
        .executableTarget(name: "VaultCheck", dependencies: ["VaultCore"], path: "Sources/VaultCheck"),
        .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"], path: "Tests/VaultCoreTests"),
    ]
)
