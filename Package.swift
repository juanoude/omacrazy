// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Omacrazy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "omacrazy", targets: ["Omacrazy"])
    ],
    targets: [
        .executableTarget(name: "Omacrazy")
    ]
)
