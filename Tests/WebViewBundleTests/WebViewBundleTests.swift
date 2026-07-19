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
    options: BundleSourceOptions? = nil,
    entries: [(path: String, data: Data, contentType: String)]
  ) throws -> BundleSource {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("wvb-test-\(UUID().uuidString)")
    let remote = tmp.appendingPathComponent("remote")
    let builtin = tmp.appendingPathComponent("builtin")
    let bundleDir = remote.appendingPathComponent(bundleName)
    try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: builtin, withIntermediateDirectories: true)

    let manifest =
      #"{"manifestVersion":1,"entries":{"\#(bundleName)":{"versions":{"\#(version)":{}},"currentVersion":"\#(version)"}}}"#
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
    try bytes.write(to: bundleDir.appendingPathComponent("\(bundleName)_\(version).wvb"))

    // Route through the wrapper's make(_:) so SourceOptions with its verification
    // fields is exercised end-to-end.
    return try BundleSource.make(
      SourceOptions(
        builtinDir: builtin.path,
        remoteDir: remote.path,
        integrity: options?.integrity,
        signature: options?.signature,
        dataRead: options?.dataRead,
        headerRead: options?.headerRead,
        indexRead: options?.indexRead
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
      options: BundleSourceOptions(
        dataRead: DataReadOptions(checksum: ChecksumReadOptions(verify: true, seed: 0))
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
    let channel = try BridgeCodec.decode(["channel": NSNull()], as: ChannelArgs.self)
    #expect(channel.channel == nil)

    #expect(throws: BridgeError.self) {
      _ = try BridgeCodec.decode(["bundleName": "app"], as: BundleVersionArgs.self)
    }
  }

  @Test("UpdateInfoPayload serializes required fields and omits nil optionals")
  func updateInfoPayload() throws {
    let info = BundleUpdateInfo(
      name: "app", version: "2.0.0", localVersion: nil, isAvailable: true,
      etag: "e", integrity: nil, signature: nil, lastModified: nil
    )
    let object = try #require(try BridgeCodec.jsonObject(UpdateInfoPayload(info)) as? [String: Any])
    #expect(object["name"] as? String == "app")
    #expect(object["version"] as? String == "2.0.0")
    #expect(object["isAvailable"] as? Bool == true)
    #expect(object["etag"] as? String == "e")
    #expect(object["localVersion"] == nil)
    #expect(object["integrity"] == nil)
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
  @Test("Source commands dispatch and serialize results (kind keyed as `type`)")
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
    #expect(items[0]["name"] as? String == "app")
    #expect(items[0]["version"] as? String == "1.0.0")
    #expect(items[0]["type"] as? String == "remote")
    #expect(items[0]["metadata"] is [String: Any])

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

    let remoteHandler = try #require(bridge.handlers["remoteGetInfo"])
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
