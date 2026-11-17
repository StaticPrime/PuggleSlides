// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuggleSlidesKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PuggleSlidesKit", targets: ["PuggleSlidesKit"]),
    ],
    targets: [
        .target(name: "PuggleSlidesKit"),
        .testTarget(name: "PuggleSlidesKitTests", dependencies: ["PuggleSlidesKit"]),
    ]
)
