import Foundation

/// Options for building a ``BundleSource`` with sensible iOS/macOS defaults.
public struct SourceOptions: Sendable {
  public var builtinDir: String?
  public var remoteDir: String?
  public var builtinManifestFilepath: String?
  public var remoteManifestFilepath: String?
  public var integrity: BundleSourceIntegrityOptions?
  public var signature: BundleSourceSignatureOptions?
  public var dataRead: DataReadOptions?
  public var headerRead: HeaderReadOptions?
  public var indexRead: IndexReadOptions?

  public init(
    builtinDir: String? = nil,
    remoteDir: String? = nil,
    builtinManifestFilepath: String? = nil,
    remoteManifestFilepath: String? = nil,
    integrity: BundleSourceIntegrityOptions? = nil,
    signature: BundleSourceSignatureOptions? = nil,
    dataRead: DataReadOptions? = nil,
    headerRead: HeaderReadOptions? = nil,
    indexRead: IndexReadOptions? = nil
  ) {
    self.builtinDir = builtinDir
    self.remoteDir = remoteDir
    self.builtinManifestFilepath = builtinManifestFilepath
    self.remoteManifestFilepath = remoteManifestFilepath
    self.integrity = integrity
    self.signature = signature
    self.dataRead = dataRead
    self.headerRead = headerRead
    self.indexRead = indexRead
  }
}

extension BundleSource {
  /// Builds a ``BundleSource`` from a `config`, filling in default directories and
  /// creating the writable `remoteDir`.
  public static func make(_ config: SourceOptions) throws -> BundleSource {
    let builtinDir = config.builtinDir ?? defaultBuiltinDir()
    let remoteDir = config.remoteDir ?? defaultRemoteDir()
    try FileManager.default.createDirectory(
      atPath: remoteDir,
      withIntermediateDirectories: true
    )
    let bundleConfig = BundleSourceConfig(
      builtinDir: builtinDir,
      remoteDir: remoteDir,
      builtinManifestFilepath: config.builtinManifestFilepath,
      remoteManifestFilepath: config.remoteManifestFilepath
    )
    let hasVerification =
      config.integrity != nil || config.signature != nil || config.dataRead != nil
      || config.headerRead != nil || config.indexRead != nil
    guard hasVerification else {
      return BundleSource(config: bundleConfig)
    }
    return try BundleSource.withOptions(
      config: bundleConfig,
      options: BundleSourceOptions(
        integrity: config.integrity,
        signature: config.signature,
        dataRead: config.dataRead,
        headerRead: config.headerRead,
        indexRead: config.indexRead
      )
    )
  }

  /// `<app resources>/bundles` — the read-only directory shipped with the app.
  public static func defaultBuiltinDir() -> String {
    // `Foundation.Bundle` because unqualified `Bundle` resolves to the FFI's
    // own bundle type in this module.
    let base = Foundation.Bundle.main.resourceURL ?? Foundation.Bundle.main.bundleURL
    return base.appendingPathComponent("bundles").path
  }

  /// `<Application Support>/<bundle id>/bundles` — the writable directory for
  /// bundles downloaded at runtime. Falls back to caches/temporary if
  /// Application Support is unavailable.
  public static func defaultRemoteDir() -> String {
    let fm = FileManager.default
    let base =
      (try? fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? fm.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fm.temporaryDirectory
    let appId = Foundation.Bundle.main.bundleIdentifier ?? "WebViewBundle"
    return
      base
      .appendingPathComponent(appId)
      .appendingPathComponent("bundles")
      .path
  }
}
