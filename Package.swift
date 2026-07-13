// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
        .executable(name: "QuotaBarAgyBridge", targets: ["QuotaBarAgyBridge"])
    ],
    targets: [
        .target(
            name: "QuotaBarCore"
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"]
        ),
        .executableTarget(
            name: "QuotaBarAgyBridge",
            dependencies: ["QuotaBarCore"]
        ),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
