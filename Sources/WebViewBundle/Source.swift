import Foundation

/// Options for building a ``BundleSource`` with sensible iOS/macOS defaults.
public struct SourceOptions: Sendable {
  public var builtinDir: String?
  public var remoteDir: String?
  public var builtinManifestFilepath: String?
  public var remoteManifestFilepath: String?

  public init(
    builtinDir: String? = nil,
    remoteDir: String? = nil,
    builtinManifestFilepath: String? = nil,
    remoteManifestFilepath: String? = nil
  ) {
    self.builtinDir = builtinDir
    self.remoteDir = remoteDir
    self.builtinManifestFilepath = builtinManifestFilepath
    self.remoteManifestFilepath = remoteManifestFilepath
  }
}

extension BundleSource {
  /// Builds a ``BundleSource`` from ``SourceOptions``, filling in default
  /// directories and creating the writable `remoteDir`.
  public static func make(_ options: SourceOptions = SourceOptions()) throws -> BundleSource {
    let builtinDir = options.builtinDir ?? defaultBuiltinDir()
    let remoteDir = options.remoteDir ?? defaultRemoteDir()
    try FileManager.default.createDirectory(
      atPath: remoteDir,
      withIntermediateDirectories: true
    )
    return BundleSource(
      config: BundleSourceConfig(
        builtinDir: builtinDir,
        remoteDir: remoteDir,
        builtinManifestFilepath: options.builtinManifestFilepath,
        remoteManifestFilepath: options.remoteManifestFilepath
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
