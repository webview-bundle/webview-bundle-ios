import Foundation

#if canImport(WebKit)
  import WebKit

  /// The native bridge for communicate with WKWebView.
  @MainActor
  public final class Bridge: NSObject, WKScriptMessageHandler {
    public typealias Handler = @MainActor (_ params: Any?) async throws -> Any?

    /// The `window.webkit.messageHandlers` name the web side posts to.
    static let messageHandlerName = "wvbIos"

    private(set) var handlers: [String: Handler] = [:]

    public override init() {
      super.init()
    }

    @discardableResult
    public func handler(_ name: String, _ handler: @escaping Handler) -> Bridge {
      handlers[name] = handler
      return self
    }

    @discardableResult
    public func add(_ handlers: any BridgeHandlers) -> Bridge {
      handlers.register(on: self)
      return self
    }

    /// Registers this bridge on `configuration` as the `wvbIos` message handler.
    func install(on configuration: WKWebViewConfiguration) {
      configuration.userContentController.add(self, name: Self.messageHandlerName)
    }

    public func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      // WebKit exposes the message handler to every frame, so an embedded
      // (possibly third-party) iframe could invoke privileged native commands.
      guard message.frameInfo.isMainFrame else {
        Log.bridge.error("invoke message dropped: not from the main frame")
        return
      }
      guard let body = message.body as? [String: Any],
        let successExpr = body["success"] as? String,
        let errorExpr = body["error"] as? String
      else {
        // No callback to reply through: the message is dropped and the web
        // `Promise` hangs with no other signal, so log it loudly.
        let name = (message.body as? [String: Any])?["name"] as? String ?? "<unknown>"
        Log.bridge.error(
          "invoke message dropped: missing success/error callback (command: \(name, privacy: .public))"
        )
        return
      }
      let name = body["name"] as? String ?? ""
      let params = body["params"] is NSNull ? nil : body["params"]
      let webView = message.webView
      let handler = handlers[name]

      // Inherits the main actor; `await` lets an async handler suspend without
      // blocking the main thread.
      Task { [weak webView] in
        let js: String
        do {
          guard let handler else {
            throw InvokeError.handlerNotFound(name)
          }
          let result = try await handler(params)
          js = "\(successExpr)(\(try Self.encode(result)))"
        } catch {
          let payload =
            (try? Self.encode(Self.errorJSON(error))) ?? "{\"message\":\"unknown error\"}"
          js = "\(errorExpr)(\(payload))"
        }
        // Usually benign (page navigated, or WebKit's "unsupported type" on an
        // `undefined` return from a successful reply), so a warning, not an error.
        do {
          _ = try await webView?.evaluateJavaScript(js)
        } catch {
          Log.bridge.warning(
            "invoke reply eval failed (command: \(name, privacy: .public)): \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }

    /// Builds the `{ code?, message }` error payload delivered to the webview.
    static func errorJSON(_ error: Swift.Error) -> [String: Any] {
      let message: String
      let code: String?
      if let failure = error as? BridgeFailure {
        message = failure.message
        code = failure.code
      } else {
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        code = nil
      }
      var json: [String: Any] = ["message": message]
      if let code { json["code"] = code }
      return json
    }

    /// Serializes a handler result to a JSON literal for a callback argument.
    static func encode(_ value: Any?) throws -> String {
      guard let value, !(value is NSNull) else { return "null" }
      guard isJSONEncodable(value), let json = jsonString(value) else {
        throw InvokeError.unencodableResult
      }
      return json
    }

    /// Whether `value` (and, recursively, its contents) is a finite JSON value
    /// that `JSONSerialization` can encode without raising.
    private static func isJSONEncodable(_ value: Any) -> Bool {
      switch value {
      case let number as NSNumber:
        // Bool/Int/Double/Float all bridge to NSNumber; reject NaN/±Infinity.
        return number.doubleValue.isFinite
      case is String, is NSNull:
        // JSON `null` decodes to NSNull and serializes back to `null`.
        return true
      case let array as [Any]:
        return array.allSatisfy(isJSONEncodable)
      case let object as [String: Any]:
        return object.values.allSatisfy(isJSONEncodable)
      default:
        return false
      }
    }

    private static func jsonString(_ value: Any) -> String? {
      guard
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
        let json = String(data: data, encoding: .utf8)
      else {
        return nil
      }
      return escapeForJS(json)
    }

    // JSON permits the raw line separators U+2028/U+2029 inside strings, but they
    // are line terminators in JavaScript source and would break the
    // `callback(<json>)` we evaluate. Built from scalars to keep the source ASCII.
    private static let lineSeparator = String(UnicodeScalar(0x2028)!)
    private static let paragraphSeparator = String(UnicodeScalar(0x2029)!)

    private static func escapeForJS(_ string: String) -> String {
      string
        .replacingOccurrences(of: lineSeparator, with: "\\u2028")
        .replacingOccurrences(of: paragraphSeparator, with: "\\u2029")
    }
  }

  @MainActor
  public protocol BridgeHandlers {
    func register(on bridge: Bridge)
  }

  /// Errors raised by the ``Bridge`` dispatch itself
  public enum InvokeError: Swift.Error, LocalizedError, BridgeFailure, Equatable {
    /// No handler was registered for the requested command name.
    case handlerNotFound(String)
    /// A handler returned a value that is not a JSON value (a custom type, or a
    /// non-finite number), so it cannot be delivered to the web side.
    case unencodableResult

    public var errorDescription: String? {
      switch self {
      case .handlerNotFound(let name):
        return "no invoke handler registered for \"\(name)\""
      case .unencodableResult:
        return "invoke handler returned a value that is not JSON-encodable"
      }
    }

    public var code: String? {
      switch self {
      case .handlerNotFound: return "handler_not_found"
      case .unencodableResult: return "unencodable_result"
      }
    }

    public var message: String { errorDescription ?? "" }
  }
#endif
