// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Photo",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Photo", targets: ["PhotoApp"]),
    .executable(name: "PhotoBench", targets: ["PhotoBench"]),
    .executable(name: "PhotoPreviewWorker", targets: ["PhotoPreviewWorker"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(name: "CCameraMemory"),
    .target(name: "PhotoCore", dependencies: ["CSQLite"]),
    .target(name: "PhotoImaging", dependencies: ["PhotoCore", "CCameraMemory"]),
    .target(
      name: "PhotoUI", dependencies: ["PhotoCore", "PhotoImaging"],
      resources: [.process("Resources")]),
    .executableTarget(name: "PhotoApp", dependencies: ["PhotoUI", "PhotoCore"]),
    .executableTarget(name: "PhotoBench", dependencies: ["PhotoCore", "PhotoImaging"]),
    .executableTarget(name: "PhotoPreviewWorker", dependencies: ["PhotoImaging"]),
    .testTarget(name: "PhotoCoreTests", dependencies: ["PhotoCore", "CSQLite"]),
    .testTarget(name: "PhotoUITests", dependencies: ["PhotoUI", "PhotoCore", "PhotoImaging"]),
  ]
)
