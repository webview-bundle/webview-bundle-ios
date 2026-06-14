import Foundation

#if canImport(WebKit)
import WebKit

/// A `WKURLSchemeHandler` that serves WebViewBundle resources for a single
/// scheme by routing requests to a UniFFI handler.
///
/// WebKit invokes the scheme-handler callbacks on the main actor. The
/// (suspending) FFI handler runs off the main thread; its result is delivered
/// back to the task on the main actor, and skipped if the task was already
/// stopped.
@MainActor
final class WebViewBundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let handler: any WebViewBundleRequestHandler
    private let onError: (@Sendable (any Swift.Error) -> Void)?

    // Tracks the tasks WebKit currently considers active. Touched only on the
    // main actor (WebKit calls start/stop there, and the completion below
    // resumes on the main actor), so a stopped task is never fed.
    private var activeTasks = Set<ObjectIdentifier>()

    nonisolated init(
        handler: any WebViewBundleRequestHandler,
        onError: (@Sendable (any Swift.Error) -> Void)? = nil
    ) {
        self.handler = handler
        self.onError = onError
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(id)

        let request = urlSchemeTask.request
        let method = HttpMethod.from(request.httpMethod)
        let uri = request.url?.absoluteString ?? ""
        let headers = request.allHTTPHeaderFields
        let url = request.url ?? URL(string: "about:blank")!
        let handler = self.handler

        // Inherits the main actor; the `await` lets the FFI handler run off-main
        // (it is `nonisolated`) and resumes here back on the main actor.
        Task {
            let result: Result<HttpResponse, any Swift.Error>
            do {
                let response = try await handler.handle(method: method, uri: uri, headers: headers)
                result = .success(response)
            } catch {
                result = .failure(error)
            }
            self.complete(urlSchemeTask, id: id, url: url, result: result)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    private func complete(
        _ task: WKURLSchemeTask,
        id: ObjectIdentifier,
        url: URL,
        result: Result<HttpResponse, any Swift.Error>
    ) {
        // Start, stop and completion are all serialized on the main actor, so
        // this check is race-free: a stopped task is never fed.
        guard activeTasks.remove(id) != nil else { return }
        switch result {
        case let .success(response):
            task.didReceive(response.makeURLResponse(url: url))
            task.didReceive(response.body)
            task.didFinish()
        case let .failure(error):
            // WebKit surfaces this as a load failure; `onError` is the
            // observability hook.
            onError?(error)
            task.didFailWithError(error)
        }
    }
}
#endif
