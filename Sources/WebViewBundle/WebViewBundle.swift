import Foundation

#if canImport(WebKit)
  import WebKit
#endif

/// The primary class for integrating webview-bundle with your app.
public final class WebViewBundle {
  public let source: BundleSource
  public let remote: Remote?
  public let updater: Updater?
  public let protocols: [WebViewBundleProtocol]

  #if canImport(WebKit)
    private let schemeHandlers: [(scheme: String, handler: WebViewBundleSchemeHandler)]
  #endif

  /// Schemes WebKit handles natively; registering a handler for one raises an
  /// uncatchable `NSException` in `setURLSchemeHandler`.
  private static let reservedSchemes: Set<String> = [
    "http", "https", "file", "ftp", "ftps", "ws", "wss", "about", "blob", "data", "javascript",
  ]

  public init(
    source: BundleSource,
    protocols: [WebViewBundleProtocol],
    remote: Remote? = nil,
    updater: Updater? = nil,
    onError: (@Sendable (any Swift.Error) -> Void)? = nil
  ) throws {
    var seen = Set<String>()
    for proto in protocols {
      let scheme = proto.scheme
      guard !scheme.isEmpty else { throw WebViewBundleError.emptyScheme }
      // URL schemes are case-insensitive and WebKit lowercases them, so
      // validate and de-duplicate on the normalized form.
      let normalized = scheme.lowercased()
      guard normalized.range(of: "^[a-z][a-z0-9+.-]*$", options: .regularExpression) != nil else {
        throw WebViewBundleError.invalidScheme(scheme)
      }
      guard !Self.reservedSchemes.contains(normalized) else {
        throw WebViewBundleError.reservedScheme(scheme)
      }
      guard seen.insert(normalized).inserted else {
        throw WebViewBundleError.duplicateScheme(scheme)
      }
    }

    self.source = source
    self.protocols = protocols
    self.remote = remote
    self.updater = updater

    #if canImport(WebKit)
      self.schemeHandlers = protocols.map { proto in
        let handler: any WebViewBundleRequestHandler
        switch proto {
        case .bundle:
          handler = BundleUrlHandler(source: source)
        case .local(_, let hosts):
          handler = LocalUrlHandler(hosts: hosts)
        }
        return (
          scheme: proto.scheme,
          handler: WebViewBundleSchemeHandler(handler: handler, onError: onError)
        )
      }
    #endif
  }

  @MainActor private static var sharedInstance: WebViewBundle?

  /// Returns the process-wide ``WebViewBundle``, building it from `config` on the
  /// first call.
  @MainActor
  public static func configure(_ config: WebViewBundleConfig) throws -> WebViewBundle {
    if let existing = sharedInstance {
      return existing
    }
    let bundle = try WebViewBundle(config: config)
    sharedInstance = bundle
    return bundle
  }

  /// Returns the shared instance that was configured already.
  ///
  /// If not explicitly configured, precondition fails.
  @MainActor
  public static var shared: WebViewBundle {
    guard let sharedInstance else {
      preconditionFailure(
        "WebViewBundle.shared was accessed before WebViewBundle.configure(_:). "
          + "Call configure(_:) (or webViewBundle(_:) / wvb(_:)) during app setup first."
      )
    }
    return sharedInstance
  }

  /// Safely returns the shared instance, or `nil` if not configured.
  @MainActor
  public static var safeShared: WebViewBundle? {
    return sharedInstance
  }

  /// The schemes this instance intercepts.
  public var schemes: [String] { protocols.map(\.scheme) }

  #if canImport(WebKit)
    /// Registers the bundle scheme handlers on `configuration`, and bridges.
    @MainActor
    public func install(on configuration: WKWebViewConfiguration, bridge: Bridge? = nil) {
      for (scheme, handler) in schemeHandlers {
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
      }
      let bridge = bridge ?? Bridge()
      bridge.add(WebViewBundleBridge(wvb: self))
      bridge.install(on: configuration)
    }

    /// Make `WKWebViewConfiguration` with the scheme handlers and invoke bridge
    /// installed.
    @MainActor
    public func makeConfiguration(bridge: Bridge? = nil) -> WKWebViewConfiguration {
      let configuration = WKWebViewConfiguration()
      install(on: configuration, bridge: bridge)
      return configuration
    }

    /// Make `WKWebView` configured to serve the registered bundles.
    @MainActor
    public func makeWebView(frame: CGRect = .zero, bridge: Bridge? = nil) -> WKWebView {
      WKWebView(frame: frame, configuration: makeConfiguration(bridge: bridge))
    }
  #endif
}

/// Errors thrown while constructing a ``WebViewBundle``.
public enum WebViewBundleError: Swift.Error, Equatable {
  /// A protocol was given an empty scheme.
  case emptyScheme
  /// A scheme is not a syntactically valid URL scheme.
  case invalidScheme(String)
  /// A scheme is one WebKit handles natively (e.g. `http`, `https`, `file`).
  case reservedScheme(String)
  /// Two protocols share the same scheme (compared case-insensitively).
  case duplicateScheme(String)
}

/// Remote endpoint configuration for ``WebViewBundleConfig``.
public struct WebViewBundleRemoteConfig: Sendable {
  /// The base URL of the remote server, e.g. `"https://bundles.example.com"`.
  public var endpoint: String

  public init(endpoint: String) {
    self.endpoint = endpoint
  }
}

/// Updater configuration for ``WebViewBundleConfig``.
public struct WebViewBundleUpdaterConfig: Sendable {
  public var remote: WebViewBundleRemoteConfig
  /// Release channel (e.g. `"stable"`, `"beta"`).
  public var channel: String?
  public var integrityPolicy: IntegrityPolicy?
  public var signatureVerifier: SignatureVerifierOptions?

  public init(
    remote: WebViewBundleRemoteConfig,
    channel: String? = nil,
    integrityPolicy: IntegrityPolicy? = nil,
    signatureVerifier: SignatureVerifierOptions? = nil
  ) {
    self.remote = remote
    self.channel = channel
    self.integrityPolicy = integrityPolicy
    self.signatureVerifier = signatureVerifier
  }

  fileprivate var updaterOptions: UpdaterOptions {
    UpdaterOptions(
      channel: channel,
      integrityPolicy: integrityPolicy,
      signatureVerifier: signatureVerifier
    )
  }
}

/// High-level configuration for ``WebViewBundle``.
public struct WebViewBundleConfig: Sendable {
  /// Source directory options. Defaults to the platform builtin/remote dirs.
  public var source: SourceOptions
  /// The protocols to register; each must use a unique, non-reserved scheme.
  public var protocols: [WebViewBundleProtocol]
  /// When set, a ``Remote`` and ``Updater`` are created and exposed.
  public var updater: WebViewBundleUpdaterConfig?
  /// Optional observer invoked (on the main actor) when a scheme handler fails.
  public var onError: (@Sendable (any Swift.Error) -> Void)?

  public init(
    source: SourceOptions = SourceOptions(),
    protocols: [WebViewBundleProtocol],
    updater: WebViewBundleUpdaterConfig? = nil,
    onError: (@Sendable (any Swift.Error) -> Void)? = nil
  ) {
    self.source = source
    self.protocols = protocols
    self.updater = updater
    self.onError = onError
  }
}

extension WebViewBundle {
  public convenience init(config: WebViewBundleConfig) throws {
    let source = try BundleSource.make(config.source)
    var remote: Remote?
    var updater: Updater?
    if let updaterConfig = config.updater {
      let createdRemote = try Remote(endpoint: updaterConfig.remote.endpoint)
      updater = try Updater(
        source: source,
        remote: createdRemote,
        options: updaterConfig.updaterOptions
      )
      remote = createdRemote
    }
    try self.init(
      source: source,
      protocols: config.protocols,
      remote: remote,
      updater: updater,
      onError: config.onError
    )
  }
}

/// Returns the process-wide ``WebViewBundle``; alias for ``WebViewBundle/configure(_:)``.
@MainActor
public func webViewBundle(_ config: WebViewBundleConfig) throws -> WebViewBundle {
  try WebViewBundle.configure(config)
}

/// Short alias for ``webViewBundle(_:)``.
@MainActor
public func wvb(_ config: WebViewBundleConfig) throws -> WebViewBundle {
  try webViewBundle(config)
}
