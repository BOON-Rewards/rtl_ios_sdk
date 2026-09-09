import Foundation
import WebKit

final class RTLBridge: NSObject, WKScriptMessageHandler {
    static let name = "inappwebview"

    private weak var sdk: RTLSdk?
    private weak var webView: WKWebView?
    private let hapticEngine: RTLHapticEngine

    init(sdk: RTLSdk, hapticEngine: RTLHapticEngine) {
        self.sdk = sdk
        self.hapticEngine = hapticEngine
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func sendToWeb(_ type: RTLNativeMessageType, fields: [String: Any] = [:]) {
        guard let json = try? serializeNativeMessage(type, fields: fields) else {
            RTLLog.error(.bridge, "Failed to serialize a bridge message")
            return
        }

        RTLLog.debug(.bridge, "Sending message to web app: \(type.rawValue)")
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(
                "window.postMessage(\(json), window.location.origin)",
                completionHandler: nil
            )
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.name,
              message.frameInfo.isMainFrame,
              isAllowed(origin: message.frameInfo.securityOrigin) else {
            RTLLog.warn(.bridge, "Ignoring a bridge message from an untrusted frame")
            return
        }
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let payload = value as? [String: Any] else {
            RTLLog.error(.bridge, "Failed to parse a bridge message")
            return
        }

        let bridgeMessage: RTLWebMessage
        do {
            guard let parsed = try RTLWebMessage.parse(payload) else {
                RTLLog.warn(.bridge, "Ignoring an unknown bridge message")
                return
            }
            bridgeMessage = parsed
        } catch {
            RTLLog.error(.bridge, "Rejected an invalid bridge message: \(error)")
            return
        }

        RTLLog.info(.bridge, "Received message from web app: \(bridgeMessage.wireName)")
        switch bridgeMessage {
        case .openExternalUrl(let url, let surface):
            sdk?.handleOpenUrl(url: url, surface: surface)
        case .authFailed:
            sdk?.handleAuthFailure()
        case .userLogout:
            sdk?.handleUserLogoutReceived()
        case .appReady:
            sdk?.handleAppReady()
        case .sessionExpired:
            sdk?.handleSessionExpired()
        case .requestLocationPermission:
            sdk?.handleLocationPermissionRequest()
        case .hapticPlay(let pattern):
            hapticEngine.play(pattern)
        case .requestNativeCapabilities:
            sendCapabilities()
        }
    }

    private func isAllowed(origin: WKSecurityOrigin) -> Bool {
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 {
            components.port = origin.port
        }
        guard let url = components.url else { return false }
        return sdk?.isAllowedWebURL(url) == true
    }

    private func sendCapabilities() {
        sendToWeb(.nativeCapabilities, fields: [
            "capabilities": [
                "haptics": hapticEngine.capabilities,
                "unifiedDeepLinks": true
            ]
        ])
    }
}

enum RTLWebMessage {
    case openExternalUrl(URL, surface: RTLSurface)
    case authFailed
    case userLogout
    case appReady
    case sessionExpired
    case requestLocationPermission
    case hapticPlay(RTLHapticPattern)
    case requestNativeCapabilities

    var wireName: String {
        switch self {
        case .openExternalUrl: return "openExternalUrl"
        case .authFailed: return "authFailed"
        case .userLogout: return "userLogout"
        case .appReady: return "appReady"
        case .sessionExpired: return "sessionExpired"
        case .requestLocationPermission: return "requestLocationPermission"
        case .hapticPlay: return "hapticPlay"
        case .requestNativeCapabilities: return "requestNativeCapabilities"
        }
    }

    static func parse(_ message: [String: Any]) throws -> RTLWebMessage? {
        guard let type = message["type"] as? String else {
            throw RTLWebMessageError.invalid("type must be a string")
        }

        switch type {
        case "openExternalUrl":
            guard let urlString = message["URL"] as? String,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                throw RTLWebMessageError.invalid("URL must be a non-empty URL string")
            }
            // Keep validating the released CrowdPlay wire contract, while
            // current SDK routing is controlled only by surface.
            guard message["forceExternalBrowser"] is Bool else {
                throw RTLWebMessageError.invalid("forceExternalBrowser must be a boolean")
            }
            guard let surfaceName = message["surface"] as? String,
                  let surface = RTLSurface(rawValue: surfaceName) else {
                throw RTLWebMessageError.invalid("surface must be a known value")
            }
            if let merchantName = message["merchantName"], !(merchantName is String) {
                throw RTLWebMessageError.invalid("merchantName must be a string")
            }
            return .openExternalUrl(url, surface: surface)
        case "authFailed": return .authFailed
        case "userLogout": return .userLogout
        case "appReady": return .appReady
        case "sessionExpired": return .sessionExpired
        case "requestLocationPermission": return .requestLocationPermission
        case "hapticPlay":
            return .hapticPlay(try RTLHapticPattern.parse(payload: message["payload"] as Any))
        case "requestNativeCapabilities": return .requestNativeCapabilities
        default: return nil
        }
    }
}

enum RTLWebMessageError: Error {
    case invalid(String)
}

enum RTLNativeMessageType: String {
    case nativeCapabilities
    case logoutRequested
    case locationPermissionStatus
    case locationUpdate
    case overlayCompleted
}

func serializeNativeMessage(
    _ type: RTLNativeMessageType,
    fields: [String: Any] = [:]
) throws -> String {
    var message = fields
    message["type"] = type.rawValue
    let data = try JSONSerialization.data(withJSONObject: message)
    guard let json = String(data: data, encoding: .utf8) else {
        throw RTLWebMessageError.invalid("message is not UTF-8")
    }
    return json
}
