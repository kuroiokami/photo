// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Photo",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Photo", targets: ["PhotoApp"]),
    .executable(name: "PhotoBench", targets: ["PhotoBench"]),
  ],
  targets: [
    .target(name: "PhotoCore"),
    .target(name: "PhotoImaging", dependencies: ["PhotoCore"]),
    .target(
      name: "PhotoUI", dependencies: ["PhotoCore", "PhotoImaging"],
      resources: [.process("Resources")]),
    .executableTarget(name: "PhotoApp", dependencies: ["PhotoUI"]),
    .executableTarget(name: "PhotoBench", dependencies: ["PhotoCore", "PhotoImaging"]),
    .testTarget(name: "PhotoCoreTests", dependencies: ["PhotoCore"]),
    .testTarget(name: "PhotoUITests", dependencies: ["PhotoUI", "PhotoCore", "PhotoImaging"]),
  ]
)
