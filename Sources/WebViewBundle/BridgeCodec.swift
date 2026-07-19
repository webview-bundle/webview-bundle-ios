import Foundation

/// Bridges raw `invoke()` payloads to typed Swift values via `Codable`.
enum BridgeCodec {
  /// Decodes the `invoke()` params object into a typed arguments value.
  static func decode<T: Decodable>(_ params: Any?, as type: T.Type) throws -> T {
    let object = params ?? [String: Any]()
    guard JSONSerialization.isValidJSONObject(object) else {
      throw BridgeError(code: "invalid_params", message: "invoke params must be an object")
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch let error as DecodingError {
      throw BridgeError(code: "invalid_params", message: describe(error))
    }
  }

  /// Encodes an `Encodable` response payload to a JSON-native value for the bridge reply.
  static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }

  private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
      return "missing required param \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? context.debugDescription : "invalid param \"\(path)\""
    case .dataCorrupted(let context):
      return context.debugDescription
    @unknown default:
      return "invalid invoke params"
    }
  }
}
