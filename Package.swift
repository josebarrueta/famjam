// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FamilyApp",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FamilyCore", targets: ["FamilyCore"]),
    ],
    targets: [
        .target(name: "FamilyCore"),
        .testTarget(name: "FamilyCoreTests", dependencies: ["FamilyCore"]),
    ]
)
