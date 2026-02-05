import Foundation
import WebKit

/// Delegate protocol for message handler events
protocol RTLMessageHandlerDelegate: AnyObject {
    func messageHandler(_ handler: RTLMessageHandler, didReceiveUserAuth accessToken: String, refreshToken: String)
    func messageHandler(_ handler: RTLMessageHandler, didReceiveUserLogout: Void)
    func messageHandler(_ handler: RTLMessageHandler, didReceiveAppReady: Void)
    func messageHandler(_ handler: RTLMessageHandler, didRequestOpenUrl url: URL, forceExternal: Bool)
}

/// Handles JavaScript messages from the RTL web app
final class RTLMessageHandler: NSObject, WKScriptMessageHandler {

    static let handlerName = "inappwebview"

    weak var delegate: RTLMessageHandlerDelegate?

    // MARK: - Message Types

    private enum MessageType: String {
        case openExternalUrl
        case userAuth
        case userLogout
        case appReady
        case locationPermissionRequest
        case locationPermissionStatus
        case locationUpdate
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == RTLMessageHandler.handlerName else { return }

        // Parse the message body
        guard let body = message.body as? String else {
            print("[RTLSdk] Invalid message body type")
            return
        }

        print("[RTLSdk] 📩 Raw message received: \(body)")

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[RTLSdk] Failed to parse message JSON: \(body)")
            return
        }

        guard let typeString = json["type"] as? String,
              let messageType = MessageType(rawValue: typeString) else {
            print("[RTLSdk] Unknown message type in: \(json)")
            return
        }

        print("[RTLSdk] Received message: \(messageType.rawValue)")
        print("[RTLSdk] 📦 Message payload: \(json)")

        switch messageType {
        case .openExternalUrl:
            handleOpenExternalUrl(json)

        case .userAuth:
            handleUserAuth(json)

        case .userLogout:
            delegate?.messageHandler(self, didReceiveUserLogout: ())

        case .appReady:
            delegate?.messageHandler(self, didReceiveAppReady: ())

        case .locationPermissionRequest, .locationPermissionStatus, .locationUpdate:
            // Not implemented in SDK - can be handled by host app if needed
            print("[RTLSdk] Location message type not handled: \(messageType.rawValue)")
        }
    }

    // MARK: - Message Handlers

    private func handleOpenExternalUrl(_ json: [String: Any]) {
        guard let urlString = json["URL"] as? String,
              let url = URL(string: urlString) else {
            print("[RTLSdk] Invalid URL in openExternalUrl message")
            return
        }

        let forceExternal: Bool
        if let forceExternalValue = json["forceExternalBrowser"] {
            if let boolValue = forceExternalValue as? Bool {
                forceExternal = boolValue
            } else if let stringValue = forceExternalValue as? String {
                forceExternal = stringValue.lowercased() == "true"
            } else {
                forceExternal = false
            }
        } else {
            forceExternal = false
        }

        delegate?.messageHandler(self, didRequestOpenUrl: url, forceExternal: forceExternal)
    }

    private func handleUserAuth(_ json: [String: Any]) {
        // Accept both "token" and "accessToken" keys
        guard let accessToken = (json["accessToken"] as? String) ?? (json["token"] as? String),
              let refreshToken = json["refreshToken"] as? String else {
            print("[RTLSdk] Missing tokens in userAuth message")
            return
        }

        delegate?.messageHandler(self, didReceiveUserAuth: accessToken, refreshToken: refreshToken)
    }
}
