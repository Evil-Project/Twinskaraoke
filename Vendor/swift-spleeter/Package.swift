// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "swift-spleeter",
    platforms: [.iOS("18.0"), .macOS("15.0"), .tvOS("18.0"), .watchOS("11.0"), .visionOS("2.0")],
    products: [.library(name: "Spleeter", targets: ["Spleeter"])],
    targets: [.target(name: "Spleeter", path: "Sources")]
)
