// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Photo",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Photo", targets: ["PhotoApp"])],
  targets: [
    .target(name: "PhotoCore"),
    .target(name: "PhotoUI", dependencies: ["PhotoCore"], resources: [.process("Resources")]),
    .executableTarget(name: "PhotoApp", dependencies: ["PhotoUI"]),
    .testTarget(name: "PhotoCoreTests", dependencies: ["PhotoCore"]),
    .testTarget(name: "PhotoUITests", dependencies: ["PhotoUI", "PhotoCore"]),
  ]
)
