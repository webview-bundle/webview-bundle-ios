// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WebViewBundle",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [
        .library(
            name: "WebViewBundle",
            targets: ["WebViewBundle"]
        ),
    ],
    targets: [
        .target(
            name: "WebViewBundle"
        ),
        .testTarget(
            name: "WebViewBundleTests",
            dependencies: ["WebViewBundle"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
