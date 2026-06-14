import Foundation

/// Common shape of the UniFFI request handlers used by the WebView integration.
///
/// Both ``BundleUrlHandler`` and ``LocalUrlHandler`` (generated into this module
/// by UniFFI) already expose this exact `handle` signature, so they conform
/// without extra code.
protocol WebViewBundleRequestHandler: AnyObject, Sendable {
    func handle(
        method: HttpMethod,
        uri: String,
        headers: [String: String]?
    ) async throws -> HttpResponse
}

extension BundleUrlHandler: WebViewBundleRequestHandler {}
extension LocalUrlHandler: WebViewBundleRequestHandler {}
