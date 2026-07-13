// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"])
    ],
    targets: [
        .target(
            name: "QuotaBarCore"
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"]
        ),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
