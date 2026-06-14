import ProjectDescription

let project = Project(
    name: "TestApp",
    packages: [
        // The WebViewBundle Swift package at the repository root.
        .local(path: ".."),
    ],
    targets: [
        .target(
            name: "TestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.wvb.ios.testapp",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": .dictionary([:]),
            ]),
            sources: ["TestApp/**/*.swift"],
            resources: [
                // Shipped as the read-only builtin bundle directory; lands at
                // `<app>/bundles`, which is `BundleSource.defaultBuiltinDir()`.
                .folderReference(path: "Fixtures/bundles"),
            ],
            dependencies: [
                .package(product: "WebViewBundle"),
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "5.0",
            ])
        ),
    ]
)
