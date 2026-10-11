// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let checksum = "5f3326f6516f218de483a0d9cb717c8269a619a6457771f0c421454fe26f01af"
let tag = "ffi/0.3.0"
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
