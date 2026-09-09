import Foundation
import os

/// Where a log line came from. Becomes the unified log's *category*, so lines
/// can be filtered structurally rather than by matching message text.
enum RTLLogArea: String, CaseIterable {
    case core = "Core"
    case webView = "WebView"
    case bridge = "Bridge"
    case location = "Location"
    case geofence = "Geofence"
    case notifications = "Notifications"
    case haptics = "Haptics"
    case store = "Store"
}

/// The SDK's logging, on Apple's unified logging system.
///
/// Subsystem and category carry what a `[RTLSdk Area LEVEL]` string prefix
/// would have carried, except the system stores them as fields: Console.app
/// shows them as columns, `log stream` filters on them with a predicate, and
/// nothing depends on parsing our text.
///
/// Uses `os_log` to write to the unified system log.
///
/// Two consequences worth knowing:
///
/// - These lines do **not** appear on stdout, so `simctl launch --console-pty`
///   will not show them. Stream them instead:
///   `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.affinaloyalty.rtlsdk"' --level debug`
///
/// - Messages are logged `%{public}@`. The unified log redacts interpolated
///   values by default, which would render every line as `<private>` and make
///   the whole thing useless for diagnosis. That choice puts the duty on call
///   sites: never log a token, a session id, or a card number.
enum RTLLog {
    /// Reverse-DNS, matching the SDK's bundle identity. Hosts filter on this.
    static let subsystem = "com.affinaloyalty.rtlsdk"

    static func debug(_ area: RTLLogArea, _ message: @autoclosure () -> String) {
        emit(.debug, area, message)
    }

    static func info(_ area: RTLLogArea, _ message: @autoclosure () -> String) {
        emit(.info, area, message)
    }

    /// The unified log has no distinct warning type; `.default` is the level
    /// Apple documents for "something worth noticing that is not an error".
    static func warn(_ area: RTLLogArea, _ message: @autoclosure () -> String) {
        emit(.default, area, message)
    }

    static func error(_ area: RTLLogArea, _ message: @autoclosure () -> String) {
        emit(.error, area, message)
    }

    /// Shows a complete URL in debug builds and removes its query and fragment
    /// in production. Login credentials, coordinates and one-time flow tokens
    /// can travel in those components.
    static func url(_ value: Any) -> String {
        guard let text = value as? String else {
            return String(describing: value)
        }

        #if DEBUG
        return text
        #else

        guard let url = URL(string: text), url.scheme != nil, url.host != nil else {
            return "<invalid URL>"
        }

        var trimmed = URLComponents(url: url, resolvingAgainstBaseURL: false)
        trimmed?.user = nil
        trimmed?.password = nil
        trimmed?.query = nil
        trimmed?.fragment = nil
        let base = trimmed?.string ?? "\(url.scheme ?? "")://\(url.host ?? "")"

        if url.user == nil && url.password == nil && url.query == nil && url.fragment == nil {
            return base
        }
        return "\(base) (URL details omitted)"
        #endif
    }

    // One handle per area, made once. OSLog objects are meant to be reused.
    private static let logs: [RTLLogArea: OSLog] = Dictionary(
        uniqueKeysWithValues: RTLLogArea.allCases.map {
            ($0, OSLog(subsystem: subsystem, category: $0.rawValue))
        }
    )

    private static func emit(
        _ type: OSLogType,
        _ area: RTLLogArea,
        _ message: () -> String
    ) {
        let log = logs[area] ?? .default
        // Skips building the string entirely when nothing is listening.
        guard log.isEnabled(type: type) else { return }
        os_log("%{public}@", log: log, type: type, message())
    }
}
