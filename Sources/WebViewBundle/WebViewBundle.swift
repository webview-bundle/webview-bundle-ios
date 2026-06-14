import Foundation

#if canImport(WebKit)
import WebKit
#endif

/// Serves WebViewBundle resources to a system `WKWebView`.
///
/// Wires one or more ``WebViewBundleProtocol``s to a `WKWebViewConfiguration` via
/// `WKURLSchemeHandler`: requests whose scheme matches a registered protocol are
/// resolved from the bundle ``source`` (or proxied to a local server) instead of
/// hitting the network.
///
/// ```swift
/// let wvb = try webViewBundle(.init(protocols: [.bundle(scheme: "app")]))
/// let webView = wvb.makeWebView()
/// webView.load(URLRequest(url: URL(string: "app://app.wvb/index.html")!))
/// ```
///
/// Keep a strong reference for the lifetime of the web view; it owns the scheme
/// handlers.
public final class WebViewBundle {
    public let source: BundleSource
    public let remote: Remote?
    public let updater: Updater?
    public let protocols: [WebViewBundleProtocol]

    #if canImport(WebKit)
    private let schemeHandlers: [(scheme: String, handler: WebViewBundleSchemeHandler)]
    #endif

    /// - Parameters:
    ///   - source: the bundle source requests are served from.
    ///   - protocols: the protocols to register; each must use a unique,
    ///     non-reserved scheme.
    ///   - onError: optional observer invoked (on the main actor) when a scheme
    ///     handler fails to serve a request.
    /// - Throws: ``WebViewBundleError`` if a scheme is empty or duplicated.
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
            guard seen.insert(scheme).inserted else {
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
            case let .local(_, hosts):
                handler = LocalUrlHandler(hosts: hosts)
            }
            return (
                scheme: proto.scheme,
                handler: WebViewBundleSchemeHandler(handler: handler, onError: onError)
            )
        }
        #endif
    }

    /// The schemes this instance intercepts.
    public var schemes: [String] { protocols.map(\.scheme) }

    #if canImport(WebKit)
    /// Registers the bundle scheme handlers on `configuration`.
    @MainActor
    public func install(on configuration: WKWebViewConfiguration) {
        for (scheme, handler) in schemeHandlers {
            configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        }
    }

    /// A fresh `WKWebViewConfiguration` with the scheme handlers installed.
    @MainActor
    public func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        install(on: configuration)
        return configuration
    }

    /// A fresh `WKWebView` configured to serve the registered bundles.
    @MainActor
    public func makeWebView(frame: CGRect = .zero) -> WKWebView {
        WKWebView(frame: frame, configuration: makeConfiguration())
    }
    #endif
}

/// Errors thrown while constructing a ``WebViewBundle``.
//
// Spelled `Swift.Error` because unqualified `Error` resolves to the FFI's own
// error enum in this module.
public enum WebViewBundleError: Swift.Error, Equatable {
    /// A protocol was given an empty scheme.
    case emptyScheme
    /// Two protocols share the same scheme.
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
///
/// When present, ``WebViewBundle/init(config:)`` builds a ``Remote`` from
/// ``remote`` and an ``Updater`` wired to the source.
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
    /// Builds a ``WebViewBundle`` from a high-level ``WebViewBundleConfig``.
    ///
    /// The source is created via ``BundleSource/make(_:)``, and — when
    /// ``WebViewBundleConfig/updater`` is set — a ``Remote`` and ``Updater`` are
    /// wired to it.
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

/// Builds a ``WebViewBundle`` from a high-level ``WebViewBundleConfig``.
public func webViewBundle(_ config: WebViewBundleConfig) throws -> WebViewBundle {
    try WebViewBundle(config: config)
}

/// Short alias for ``webViewBundle(_:)``.
public func wvb(_ config: WebViewBundleConfig) throws -> WebViewBundle {
    try webViewBundle(config)
}
