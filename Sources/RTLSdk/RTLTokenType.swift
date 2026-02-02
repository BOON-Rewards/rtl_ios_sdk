import Foundation

/// Push notification token type
public enum RTLTokenType: String {
    /// Apple Push Notification Service token
    case apns = "apns"

    /// Firebase Cloud Messaging token
    case fcm = "fcm"
}
