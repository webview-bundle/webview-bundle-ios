import Foundation

/// Common shape of the UniFFI request handlers used by the WebView integration.
protocol WebViewBundleRequestHandler: AnyObject, Sendable {
  func handle(
    method: HttpMethod,
    uri: String,
    headers: [String: String]?
  ) async throws -> HttpResponse
}

extension BundleUrlHandler: WebViewBundleRequestHandler {}
extension LocalUrlHandler: WebViewBundleRequestHandler {}
