// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let checksum = "1f5524108dfd8102f486481840fe1105e4f393f405e74c2d429d32dc0650b5ae"
let tag = "prerelease/a28897c"
let url =
  "https://github.com/webview-bundle/webview-bundle/releases/download/\(tag)/WebViewBundleFFI.xcframework.zip"

let package = Package(
  name: "WebViewBundle",
  platforms: [.macOS(.v12), .iOS(.v16)],
  products: [
    .library(
      name: "WebViewBundle",
      targets: ["WebViewBundle"]
    )
  ],
  dependencies: [
    // Command plugin used by Swift Package Index to build DocC documentation.
    // It is a *command* plugin, so it is NOT wired into any target's `plugins:`.
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
  ],
  targets: [
    .binaryTarget(name: "WebViewBundleFFI", url: url, checksum: checksum),
    .target(
      name: "WebViewBundle",
      dependencies: [.target(name: "WebViewBundleFFI")],
      linkerSettings: [
        .linkedFramework("SystemConfiguration"),
        .linkedFramework("Security"),
        .linkedFramework("CoreFoundation"),
      ]
    ),
    .testTarget(
      name: "WebViewBundleTests",
      dependencies: [.target(name: "WebViewBundle")]
    ),
  ],
  // The whole package is compiled in the Swift 5 language mode: the
  // uniffi-generated bindings (WebViewBundleLibrary.swift) are not Swift 6
  // strict-concurrency clean (async callback-interface scaffolding).
  swiftLanguageModes: [.v5]
)
