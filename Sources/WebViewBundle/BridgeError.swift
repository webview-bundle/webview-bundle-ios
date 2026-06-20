import Foundation

/// A Swift error that maps to the web-facing `{ code?, message }` bridge error
/// shape. Conform a custom error to deliver a `code` alongside its `message`
public protocol BridgeFailure: Swift.Error {
  /// Optional machine-readable code, omitted from the payload when `nil`.
  var code: String? { get }
  /// Human-readable message, always present in the payload.
  var message: String { get }
}

/// The canonical `{ code?, message }` error thrown to reject an `invoke()`
/// command. Other thrown errors are encoded with their localized description as
/// `message` and no `code`.
public struct BridgeError: BridgeFailure, Equatable {
  public var code: String?
  public var message: String

  public init(code: String? = nil, message: String) {
    self.code = code
    self.message = message
  }
}
