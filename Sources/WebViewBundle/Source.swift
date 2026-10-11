import Foundation

/// Options for building a ``Source`` with sensible iOS/macOS defaults.
public struct SourceOptions: Sendable {
  public var builtinDir: String?
  public var remoteDir: String?
  public var builtinManifestFilepath: String?
  public var remoteManifestFilepath: String?
  public var integrity: SourceIntegrityOptions?
  public var dataReadOptions: DataReadOptions?
  public var headerReadOptions: HeaderReadOptions?
  public var indexReadOptions: IndexReadOptions?
  public var removeBundleChunkSize: UInt32?

  public init(
    builtinDir: String? = nil,
    remoteDir: String? = nil,
    builtinManifestFilepath: String? = nil,
    remoteManifestFilepath: String? = nil,
    integrity: SourceIntegrityOptions? = nil,
    dataReadOptions: DataReadOptions? = nil,
    headerReadOptions: HeaderReadOptions? = nil,
    indexReadOptions: IndexReadOptions? = nil,
    removeBundleChunkSize: UInt32? = nil
  ) {
    self.builtinDir = builtinDir
    self.remoteDir = remoteDir
    self.builtinManifestFilepath = builtinManifestFilepath
    self.remoteManifestFilepath = remoteManifestFilepath
    self.integrity = integrity
    self.dataReadOptions = dataReadOptions
    self.headerReadOptions = headerReadOptions
    self.indexReadOptions = indexReadOptions
    self.removeBundleChunkSize = removeBundleChunkSize
  }
}

extension Source {
  /// Builds a ``Source`` from a `config`, filling in default directories and
  /// creating the writable `remoteDir`.
  public static func make(_ config: SourceOptions) throws -> Source {
    let builtinDir = config.builtinDir ?? defaultBuiltinDir()
    let remoteDir = config.remoteDir ?? defaultRemoteDir()
    try FileManager.default.createDirectory(
      atPath: remoteDir,
      withIntermediateDirectories: true
    )
    return try Source(
      config: SourceConfig(
        builtinDir: builtinDir,
        remoteDir: remoteDir,
        builtinManifestFilepath: config.builtinManifestFilepath,
        remoteManifestFilepath: config.remoteManifestFilepath,
        integrity: config.integrity,
        dataReadOptions: config.dataReadOptions,
        headerReadOptions: config.headerReadOptions,
        indexReadOptions: config.indexReadOptions,
        removeBundleChunkSize: config.removeBundleChunkSize
      ))
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
