import Foundation
import Testing
import os

@testable import WebViewBundle

@Suite("WebViewBundle")
struct WebViewBundleTests {
  /// Builds a one-bundle source on disk: a `.wvb` with the given entries plus a
  /// manifest pinning it as the current remote version. Returns the source.
  private func makeSource(
    bundleName: String = "app",
    version: String = "1.0.0",
    options: SourceOptions? = nil,
    entries: [(path: String, data: Data, contentType: String)]
  ) throws -> Source {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("wvb-test-\(UUID().uuidString)")
    let remote = tmp.appendingPathComponent("remote")
    let builtin = tmp.appendingPathComponent("builtin")
    let bundleDir = remote.appendingPathComponent(bundleName)
    try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: builtin, withIntermediateDirectories: true)

    let manifest =
      #"{"manifestVersion":1,"bundles":{"\#(bundleName)":{"versions":{"\#(version)":{}},"currentVersion":"\#(version)"}}}"#
    try Data(manifest.utf8).write(to: remote.appendingPathComponent("manifest.json"))

    let builder = BundleBuilder(version: nil)
    for entry in entries {
      _ = try builder.insertEntry(
        path: entry.path,
        data: entry.data,
        contentType: entry.contentType,
        headers: nil
      )
    }
    let bundle = try builder.build(options: nil)
    let bytes = try writeBundleToBytes(bundle: bundle)
    try bytes.write(to: bundleDir.appendingPathComponent("\(version).wvb"))

    // Route through the wrapper's make(_:) so SourceOptions with its verification
    // fields is exercised end-to-end.
    return try Source.make(
      SourceOptions(
        builtinDir: builtin.path,
        remoteDir: remote.path,
        integrity: options?.integrity,
        dataReadOptions: options?.dataReadOptions,
        headerReadOptions: options?.headerReadOptions,
        indexReadOptions: options?.indexReadOptions
      )
    )
  }

  @Test("BundleProtocolHandler serves an entry as 200")
  func bundleHandlerServesEntry() async throws {
    let html = "<!DOCTYPE html><title>hi</title>"
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data(html.utf8), contentType: "text/html")
    ])
    let handler: any WebViewBundleRequestHandler = BundleProtocolHandler(source: source)

    let response = try await handler.handle(
      method: .get,
      uri: "app://app.wvb/index.html",
      headers: nil,
      body: nil
    )

    #expect(response.status == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == html)
    #expect(response.headers["content-type"]?.contains("text/html") == true)
  }

  @Test("Missing entry returns 404")
  func missingEntryIs404() async throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    let handler: any WebViewBundleRequestHandler = BundleProtocolHandler(source: source)

    let response = try await handler.handle(
      method: .get,
      uri: "app://app.wvb/missing.html",
      headers: nil,
      body: nil
    )

    #expect(response.status == 404)
  }

  @Test("SourceOptions.verification is applied (read-time data checksum) and serves")
  func sourceVerificationServesEntry() async throws {
    let html = "<!DOCTYPE html><title>hi</title>"
    let source = try makeSource(
      options: SourceOptions(
        dataReadOptions: DataReadOptions(checksum: ChecksumReadOptions(verify: true, seed: 0))
      ),
      entries: [
        (path: "/index.html", data: Data(html.utf8), contentType: "text/html")
      ]
    )
    let handler: any WebViewBundleRequestHandler = BundleProtocolHandler(source: source)

    let response = try await handler.handle(
      method: .get,
      uri: "app://app.wvb/index.html",
      headers: nil,
      body: nil
    )

    #expect(response.status == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == html)
  }

  @Test("Facade exposes its schemes")
  func facadeSchemes() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    let wvb = try WebViewBundle(
      source: source,
      protocols: [
        .bundle(scheme: "app"), .local(scheme: "local", hosts: ["myapp": "http://localhost:8080"]),
      ]
    )

    #expect(wvb.schemes == ["app", "local"])
    #expect(wvb.remote == nil)
    #expect(wvb.updater == nil)
  }

  @Test("Duplicate scheme throws instead of trapping")
  func duplicateSchemeThrows() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    #expect(throws: WebViewBundleError.duplicateScheme("app")) {
      _ = try WebViewBundle(
        source: source,
        protocols: [.bundle(scheme: "app"), .bundle(scheme: "app")]
      )
    }
  }

  @Test("Empty scheme throws instead of trapping")
  func emptySchemeThrows() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    #expect(throws: WebViewBundleError.emptyScheme) {
      _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "")])
    }
  }

  @Test("Invalid scheme throws instead of trapping")
  func invalidSchemeThrows() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    #expect(throws: WebViewBundleError.invalidScheme("1app")) {
      _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "1app")])
    }
  }

  @Test("Reserved scheme throws instead of trapping")
  func reservedSchemeThrows() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    #expect(throws: WebViewBundleError.reservedScheme("https")) {
      _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "https")])
    }
  }

  @Test("Case-insensitive duplicate scheme throws")
  func caseInsensitiveDuplicateSchemeThrows() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    #expect(throws: WebViewBundleError.duplicateScheme("App")) {
      _ = try WebViewBundle(
        source: source,
        protocols: [.bundle(scheme: "app"), .bundle(scheme: "App")]
      )
    }
  }

  @Test("HttpMethod maps from request strings")
  func httpMethodFrom() {
    #expect(HttpMethod.from("get") == .get)
    #expect(HttpMethod.from("POST") == .post)
    #expect(HttpMethod.from(nil) == .get)
    #expect(HttpMethod.from("weird") == .get)
  }

  // MARK: - Bridge

  @Test("BridgeCodec decodes typed args and reports missing keys")
  func bridgeCodecDecode() throws {
    let args = try BridgeCodec.decode(
      ["bundleName": "app", "version": "1.0.0"], as: BundleVersionArgs.self)
    #expect(args.bundleName == "app")
    #expect(args.version == "1.0.0")

    // An optional reads nil from an explicit JS `null`.
    let channel = try BridgeCodec.decode(["channel": NSNull()], as: RemoteGetUpdateArgs.self)
    #expect(channel.channel == nil)

    #expect(throws: BridgeError.self) {
      _ = try BridgeCodec.decode(["bundleName": "app"], as: BundleVersionArgs.self)
    }
  }

  @Test("Update document preserves nested bundles and omits nil fields")
  func updatePayload() throws {
    let update = Update(
      id: "update-1", createdAt: "2026-10-09T00:00:00Z", runtimeVersion: 1,
      bundles: [
        BundleUpdate(
          name: "app", version: "2.0.0", downloadUrl: nil,
          integrity: nil, metadata: ["release": "stable"])
      ],
      metadata: [:]
    )
    let object = try #require(try BridgeCodec.jsonObject(UpdatePayload(update)) as? [String: Any])
    #expect(object["id"] as? String == "update-1")
    #expect(object["runtimeVersion"] as? Int == 1)
    let bundles = try #require(object["bundles"] as? [[String: Any]])
    #expect(bundles[0]["name"] as? String == "app")
    #expect(bundles[0]["integrity"] == nil)
    #expect(bundles[0]["metadata"] as? [String: String] == ["release": "stable"])
  }

  @Test("Updater results encode discriminants and native error codes")
  func updaterResultPayload() throws {
    let result = UpdaterDownloadResult(
      name: "app", version: "2", integrity: nil, metadata: nil,
      result: .error(.CoreCancelled(message: "cancelled")))
    let object = try #require(
      try BridgeCodec.jsonObject(UpdaterDownloadResultPayload(result)) as? [String: Any])
    let outcome = try #require(object["result"] as? [String: String])
    #expect(outcome == ["type": "error", "code": "core.cancelled", "message": "cancelled"])
    #expect(
      UpdaterInstallResultKind.stagedVersionNotMatched.bridgePayload.type
        == "staged_version_not_matched")
    #expect(UpdaterRollbackResultKind.rolledBack.bridgePayload.type == "rolled_back")
  }

  @MainActor
  @Test("errorJSON encodes BridgeError as { code?, message }")
  func errorJSONShape() {
    let withCode = Bridge.errorJSON(BridgeError(code: "x", message: "boom"))
    #expect(withCode["message"] as? String == "boom")
    #expect(withCode["code"] as? String == "x")

    let withoutCode = Bridge.errorJSON(BridgeError(message: "plain"))
    #expect(withoutCode["message"] as? String == "plain")
    #expect(withoutCode["code"] == nil)

    struct Other: Swift.Error {}
    let other = Bridge.errorJSON(Other())
    #expect(other["message"] != nil)
    #expect(other["code"] == nil)
  }

  @MainActor
  @Test("Source commands dispatch and serialize nested manifest items")
  func bridgeSourceCommands() async throws {
    let html = "<!DOCTYPE html><title>hi</title>"
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data(html.utf8), contentType: "text/html")
    ])
    let wvb = try WebViewBundle(source: source, protocols: [.bundle(scheme: "app")])
    let bridge = Bridge()
    bridge.add(WebViewBundleBridge(wvb: wvb))

    let listHandler = try #require(bridge.handlers["sourceListBundles"])
    let items = try #require(try await listHandler(nil) as? [[String: Any]])
    #expect(items.count == 1)
    #expect(items[0]["source"] as? String == "remote")
    let item = try #require(items[0]["item"] as? [String: Any])
    #expect(item["name"] as? String == "app")
    #expect(item["version"] as? String == "1.0.0")
    #expect(item["status"] as? String == "current")
    #expect(item["data"] is [String: Any])

    let resolveHandler = try #require(bridge.handlers["sourceResolveFilepath"])
    let path = try await resolveHandler(["bundleName": "app"]) as? String
    #expect(path?.hasSuffix(".wvb") == true)
  }

  @MainActor
  @Test("Remote/updater commands reject with BridgeError when not configured")
  func bridgeRejectsWhenCapabilityMissing() async throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    let wvb = try WebViewBundle(source: source, protocols: [.bundle(scheme: "app")])
    let bridge = Bridge()
    bridge.add(WebViewBundleBridge(wvb: wvb))

    let remoteHandler = try #require(bridge.handlers["remoteGetUpdate"])
    await #expect(
      throws: BridgeError(code: "remote_not_initialized", message: "remote is not initialized.")
    ) {
      _ = try await remoteHandler(["bundleName": "app"])
    }

    let updaterHandler = try #require(bridge.handlers["updaterGetUpdate"])
    await #expect(
      throws: BridgeError(code: "updater_not_initialized", message: "updater is not initialized.")
    ) {
      _ = try await updaterHandler(["bundleName": "app"])
    }
  }

  @MainActor
  @Test("install auto-registers the standard bridge commands")
  func installRegistersBridgeCommands() throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
    ])
    let wvb = try WebViewBundle(source: source, protocols: [.bundle(scheme: "app")])
    let bridge = Bridge().handler("ping") { _ in "pong" }
    _ = wvb.makeConfiguration(bridge: bridge)

    // User command preserved alongside the auto-registered standard commands.
    #expect(bridge.handlers["ping"] != nil)
    for name in ["sourceListBundles", "remoteDownload", "updaterInstall"] {
      #expect(bridge.handlers[name] != nil)
    }
  }

  @MainActor
  @Test("Bridge stages, installs, rolls back, removes and prunes remote bundles")
  func bridgeUpdateLifecycle() async throws {
    let source = try makeSource(entries: [
      (path: "/index.html", data: Data("v1".utf8), contentType: "text/html")
    ])
    let currentPath = try source.getRemoteBundleFilepath(bundleName: "app", version: "1.0.0")
    let root = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
      .deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let remote = try Remote(baseUrl: "http://localhost:1")
    let updater = try Updater(
      source: source, remote: remote,
      updateFilepath: root.appendingPathComponent("update.json").path, options: nil)
    let wvb = try WebViewBundle(
      source: source, protocols: [.bundle(scheme: "app")], remote: remote, updater: updater)
    let bridge = Bridge()
    bridge.add(WebViewBundleBridge(wvb: wvb))
    func invoke(_ name: String, _ params: [String: Any]? = nil) async throws -> Any? {
      let handler = try #require(bridge.handlers[name])
      return try await handler(params)
    }
    let builder = BundleBuilder(version: nil)
    _ = try builder.insertEntry(
      path: "/index.html", data: Data("v2".utf8), contentType: "text/html", headers: nil)
    let bytes = try writeBundleToBytes(bundle: builder.build(options: nil))
    let newPath = try source.getRemoteBundleFilepath(bundleName: "app", version: "2.0.0")
    try bytes.write(to: URL(fileURLWithPath: newPath))

    let staged = try #require(
      try await invoke(
        "sourceStageRemoteBundles",
        [
          "items": [
            "app": ["version": "2.0.0", "data": ["metadata": ["release": "stable"]]]
          ]
        ]) as? [[String: Any]])
    #expect(staged[0]["kind"] as? String == "staged")
    #expect(
      try await invoke("sourceGetRemoteStagedVersion", ["bundleName": "app"]) as? String == "2.0.0")
    #expect(try await source.getVersion(bundleName: "app")?.version == "1.0.0")

    // Cache the old descriptor before install; serving must switch when the version changes.
    let cached = try await source.load(bundleName: "app")
    let mismatch = try #require(
      try await invoke("updaterInstall", ["targets": [["name": "app", "version": "3.0.0"]]])
        as? [[String: Any]])
    #expect((mismatch[0]["result"] as? [String: String])?["type"] == "staged_version_not_matched")
    let installed = try #require(
      try await invoke("updaterInstall", ["targets": [["name": "app"]]]) as? [[String: Any]])
    #expect((installed[0]["result"] as? [String: String])?["type"] == "installed")
    #expect(installed[0]["installVersion"] as? String == "2.0.0")
    #expect(installed[0]["targetVersion"] == nil)
    #expect(try await source.getRemotePreviousVersion(bundleName: "app") == "1.0.0")
    let served = try await source.load(bundleName: "app").getData(path: "/index.html")
    #expect(served == Data("v2".utf8))
    #expect(try await cached.getData(path: "/index.html") == Data("v1".utf8))

    let rolledBack = try #require(
      try await invoke("updaterRollback", ["targets": [["name": "app"]]]) as? [[String: Any]])
    #expect((rolledBack[0]["result"] as? [String: String])?["type"] == "rolled_back")
    #expect(rolledBack[0]["rollbackVersion"] as? String == "1.0.0")
    #expect(try await source.getVersion(bundleName: "app")?.version == "1.0.0")

    let removed = try #require(
      try await invoke(
        "sourceRemoveRemoteBundles",
        [
          "items": [
            "app": ["versions": ["1.0.0"]]
          ]
        ]) as? [[String: Any]])
    #expect(removed[0]["kind"] as? String == "in_use")
    let pruned = try #require(
      try await invoke("sourcePruneRemoteBundles", ["bundleNames": ["app"]]) as? [[String: Any]])
    #expect(pruned[0]["name"] as? String == "app")
    #expect(pruned[0]["prunedVersions"] is [String])
    #expect(try await invoke("sourceGetVersion", ["bundleName": "missing"]) == nil)
    await #expect(throws: BridgeError.self) {
      _ = try await invoke(
        "updaterDownload", ["bundleUpdates": [], "options": ["concurrency": -1]])
    }
  }

  @Test("LogLevel maps to the expected OSLogType (the core-tracing contract)")
  func logLevelMapping() {
    #expect(LogLevel.trace.osLogType == .debug)
    #expect(LogLevel.debug.osLogType == .debug)
    #expect(LogLevel.info.osLogType == .info)
    #expect(LogLevel.warning.osLogType == .default)
    #expect(LogLevel.error.osLogType == .error)
    // Ordering gates forwarded core events by severity.
    #expect(LogLevel.trace < LogLevel.error)
  }
}
