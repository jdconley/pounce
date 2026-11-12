// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PounceKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PounceKit", targets: ["PounceKit"]),
        .executable(name: "pounce-e2e", targets: ["pounce-e2e"]),
    ],
    targets: [
        .target(name: "PounceKit"),
        .executableTarget(name: "pounce-e2e", dependencies: ["PounceKit"]),
        // `Fixtures/` holds JSON the tests read by path (like `apps/play-api/fixtures`), not bundle resources.
        .testTarget(name: "PounceKitTests", dependencies: ["PounceKit"], exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
