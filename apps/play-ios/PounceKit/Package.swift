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
        .testTarget(name: "PounceKitTests", dependencies: ["PounceKit"]),
    ],
    swiftLanguageModes: [.v6]
)
