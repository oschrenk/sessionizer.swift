// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "Sessionizer",
  platforms: [
    .macOS("27.0"),
  ],
  dependencies: [
    .package(url: "https://github.com/LebJe/TOMLKit", exact: "0.6.0"),
    .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
  ],
  targets: [
    .executableTarget(
      name: "Sessionizer",
      dependencies: [
        .product(name: "TOMLKit", package: "TOMLKit"),
        .product(name: "Yams", package: "Yams"),
      ],
      path: "Sources"
    ),
    .testTarget(
      name: "test",
      dependencies: ["Sessionizer"],
      path: "Tests",
      resources: [.copy("testdata")]
    ),
  ]
)
