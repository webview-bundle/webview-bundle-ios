// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let checksum = "8184364fc8f2e5b624debe4023f5c219e32190fecffc49a1cb39c535b41f88fd"
let tag = "prerelease/4513cab"
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
  swiftLanguageModes: [.v6]
)
