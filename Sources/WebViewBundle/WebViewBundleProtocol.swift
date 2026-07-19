import Foundation

/// Binds a URL scheme handled inside a `WKWebView` to a WebViewBundle request
/// handler.
///
/// The bundle name is resolved from the first label of the request host, e.g.
/// `app://app.wvb/index.html` -> bundle `"app"`.
///
/// `WKWebView` only allows scheme handlers for non-reserved schemes, so use a
/// custom scheme (not `http`/`https`).
public enum WebViewBundleProtocol: Sendable {
  /// Serves entries from the WebViewBundle source.
  case bundle(scheme: String)

  /// Proxies requests to local HTTP servers.
  ///
  /// `hosts` maps a virtual host to a local base URL. Unlike ``bundle(scheme:)``,
  /// whose bundle name is the *first label* of the host, a `hosts` key is matched
  /// against the **entire** request URL host.
  case local(scheme: String, hosts: [String: String])

  /// The URL scheme this protocol handles.
  public var scheme: String {
    switch self {
    case .bundle(let scheme): return scheme
    case .local(let scheme, _): return scheme
    }
  }
}
