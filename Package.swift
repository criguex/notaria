// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aria",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "aria-capture", targets: ["aria-capture"])
    ],
    dependencies: [
        .package(path: "Vendor/whisper.cpp")
    ],
    targets: [
        .executableTarget(
            name: "aria-capture",
            dependencies: [
                .product(name: "whisper", package: "whisper.cpp")
            ],
            path: "Sources/aria-capture",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["aria-capture"],
            path: "Tests/AriaTests"
        )
    ]
)
