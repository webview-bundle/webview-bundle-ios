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

After upgrading the FFI, use **Product → Clean Build Folder** in Xcode before
building again. Xcode can retain a precompiled `wvb_ffi` module from the previous
release and fail with `wvb_ffi.h has been modified since the module file ... was
built`. For SwiftPM builds, run `swift package clean` instead. Clean the build
folder of the app consuming this package as well if it reports the same error.

## TestApp & E2E

`TestApp/` is a tuist-generated SwiftUI app that serves a **real builtin `.wvb`**
to a `WKWebView` through the `testapp://` scheme, and `e2e/` drives it with
Appium.

```sh
cd e2e && yarn install && yarn test
```

The testbed UI and shared tests come from
`webview-bundle/playground/webviews/testbed`. The committed builtin bundle is
0.4.0; `e2e/fixtures` contains the 0.4.1/0.4.2 update bundles and the matching
0.4.0 testing package archive. This keeps the UI and tests in sync without
requiring a registry release. Tests interact with form inputs and buttons, then
verify the rendered results and the actual page version after install/rollback.

To regenerate them, build `@wvb/bridge` and `@wvb/node` in the core workspace,
then run from that workspace:

```sh
yarn workspace @wvb-playground/webview-testbed mobile-fixtures "$PWD/../webview-bundle-android" "$PWD/../webview-bundle-ios"
```

Run `yarn install` in each mobile repository's `e2e` directory afterward to update
the archive checksum in its lockfile. The iOS test app accepts `WVB_REMOTE_URL`
and the Android test app accepts a `wvbRemoteUrl` launch extra for a local remote.
The E2E harness sets these automatically; ordinary launches use the playground
remote. Nothing is published by the fixture-generation command.


## License

MIT License
