import Foundation
import os

/// Severity of an SDK log event; mirrors Rust `tracing` levels so core events
/// can forward into the same pipeline (see ``CoreLog``).
enum LogLevel: Int, Sendable, Comparable {
  case trace, debug, info, warning, error

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

  /// `os` has no `warning`, so it folds into `.default`.
  var osLogType: OSLogType {
    switch self {
    case .trace, .debug: return .debug
    case .info: return .info
    case .warning: return .default
    case .error: return .error
    }
  }
}

/// Unified `os.Logger` channels. Filter on `subsystem == "webview-bundle"` to
/// see Swift-side and Rust-core logs together.
enum Log {
  static let subsystem = "webview-bundle"

  static let bridge = Logger(subsystem: subsystem, category: "bridge")
  static let core = Logger(subsystem: subsystem, category: "core")
}

/// Seam for forwarding the Rust core's `tracing` into the unified `core`
/// channel.
enum CoreLog {
  /// `message` is already formatted by the core; `target` is its module path.
  /// Logged `.public` since tracing is an explicit opt-in, so the core must not
  /// emit user PII into tracing messages.
  static func forward(level: LogLevel, target: String, message: String) {
    Log.core.log(
      level: level.osLogType,
      "[\(target, privacy: .public)] \(message, privacy: .public)")
  }
}

extension WebViewBundle {
  /// The unified-logging subsystem the SDK logs under.
  public static let logSubsystem = Log.subsystem
}
