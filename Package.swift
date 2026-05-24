// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let checksum = "<CHECKSUM>"
let tag = "<TAG>"
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
  targets: [
    .binaryTarget(name: "WebViewBundleFFI", url: url, checksum: checksum),
    .target(
      name: "WebViewBundle",
      dependencies: [.target(name: "WebViewBundleFFI")]
    ),
    .testTarget(
      name: "WebViewBundleTests",
      dependencies: [.target(name: "WebViewBundle")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
