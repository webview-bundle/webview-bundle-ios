import Foundation

/// Common shape of the UniFFI request handlers used by the WebView integration.
protocol WebViewBundleRequestHandler: AnyObject, Sendable {
  func handle(
    method: HttpMethod,
    uri: String,
    headers: [String: String]?,
    body: Data?
  ) async throws -> HttpResponse
}

extension BundleProtocolHandler: WebViewBundleRequestHandler {}
extension ProxyProtocolHandler: WebViewBundleRequestHandler {}
