// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuggleSlidesKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PuggleSlidesKit", targets: ["PuggleSlidesKit"]),
        // Keeping the app up to date: shared by the app and its update installer service.
        .library(name: "PuggleUpdate", targets: ["PuggleUpdate"]),
    ],
    targets: [
        .target(name: "PuggleSlidesKit"),
        .target(name: "PuggleUpdate"),
        .testTarget(name: "PuggleSlidesKitTests", dependencies: ["PuggleSlidesKit"]),
        .testTarget(name: "PuggleUpdateTests", dependencies: ["PuggleUpdate"]),
    ]
)
