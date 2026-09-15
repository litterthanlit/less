// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "LessCore",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "LessCore", targets: ["LessCore"])
  ],
  targets: [
    .target(name: "LessCore"),
    .testTarget(
      name: "LessCoreTests",
      dependencies: ["LessCore"]
    ),
  ]
)
