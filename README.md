# webview-bundle-ios

iOS Swift package for WebViewBundle. The native FFI module is built in
[webview-bundle](https://github.com/webview-bundle/webview-bundle)
and pulled into this package from its GitHub releases.

## Prerequisites

This repository uses [mise](https://mise.jdx.dev) to manage its toolchain. The
required versions of Node.js and Tuist are pinned in `mise.toml`.

[Install mise](https://mise.jdx.dev/getting-started.html), then install the
pinned tools from the repository root:

```sh
mise install
```

## Installing / updating the FFI module

`scripts/install.mjs` fetches a release from the upstream repository and wires
it into this package:

- extracts the Swift bindings from the `apple.zip` asset into `Sources/WebViewBundle/`
- resolves the checksum of `WebViewBundleFFI.xcframework.zip` (from the digest in
  the GitHub release metadata, or by hashing the archive) and writes both the
  checksum and the release tag into `Package.swift`

```sh
# install a release (tag ffi/0.1.0)
node scripts/install.mjs 0.1.0

# or an explicit tag
node scripts/install.mjs ffi/0.1.0

# install a prerelease build for a commit (tag prerelease/<sha>)
node scripts/install.mjs --prerelease a3f693a
node scripts/install.mjs prerelease/a3f693a

# install the latest ffi/* release
node scripts/install.mjs latest
```

Tags follow the upstream convention: `ffi/<version>` for releases and
`prerelease/<sha>` for prereleases. Run `node scripts/install.mjs --help` for
all options.

## TestApp & E2E

`TestApp/` is a tuist-generated SwiftUI app that serves a **real builtin `.wvb`**
to a `WKWebView` through the `testapp://` scheme, and `e2e/` drives it with
Appium.

```sh
cd e2e && yarn install && yarn test
```

## License

MIT License
