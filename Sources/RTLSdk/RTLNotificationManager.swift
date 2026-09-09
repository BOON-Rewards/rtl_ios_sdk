import Foundation
import UserNotifications

/// Manages local notifications with rate limiting rules
final class RTLNotificationManager {
    static let identifierPrefix = "com.affinaloyalty.rtlsdk.offer."
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationHistory: [NotificationRecord] = []

    // Rate limiting configuration
    private let dailyLimit = 2
    private let weeklyLimit = 7
    private let monthlyLimit = 20
    private let merchantCooldownHours = 24
    private let merchantWeeklyLimit = 3
    private let merchantMonthlyLimit = 5
    private let allowedHourStart = 10
    private let allowedHourEnd = 20

    /// Debug mode - bypass time window restriction
    #if DEBUG
    private let debugBypassTimeWindow = true
    #else
    private let debugBypassTimeWindow = false
    #endif

    private let historyKey = "rtl_notification_history"

    struct NotificationRecord: Codable {
        let storeId: String
        let merchantId: String
        let timestamp: Date
    }

    init() {
        // The host owns the notification center delegate and its presentation policy.
        loadHistory()
    }

    /// Request notification permission
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            RTLLog.debug(.notifications, "Notification permission granted: \(granted)")
            return granted
        } catch {
            RTLLog.error(.notifications, "Notification permission error: \(error)")
            return false
        }
    }

    /// Check if a notification can be shown for the given store
    func canShowNotification(for store: RTLStore) -> Bool {
        let now = Date()
        let calendar = Calendar.current

        // Check time window (10:00 - 20:00)
        let hour = calendar.component(.hour, from: now)
        if !debugBypassTimeWindow {
            guard hour >= allowedHourStart && hour < allowedHourEnd else {
                RTLLog.debug(.notifications, "Blocked: Outside time window (\(hour):00)")
                return false
            }
        } else {
            RTLLog.debug(.notifications, "🔧 Debug mode: bypassing time window check (current hour: \(hour):00)")
        }

        // Check daily limit
        let todayNotifications = notificationHistory.filter { calendar.isDateInToday($0.timestamp) }
        guard todayNotifications.count < dailyLimit else {
            RTLLog.debug(.notifications, "Blocked: Daily limit reached (\(todayNotifications.count)/\(dailyLimit))")
            return false
        }

        // Check weekly limit
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let weekNotifications = notificationHistory.filter { $0.timestamp >= weekStart }
        guard weekNotifications.count < weeklyLimit else {
            RTLLog.debug(.notifications, "Blocked: Weekly limit reached")
            return false
        }

        // Check monthly limit
        let monthStart = calendar.date(byAdding: .day, value: -30, to: now)!
        let monthNotifications = notificationHistory.filter { $0.timestamp >= monthStart }
        guard monthNotifications.count < monthlyLimit else {
            RTLLog.debug(.notifications, "Blocked: Monthly limit reached")
            return false
        }

        // Check merchant cooldown (24 hours)
        let merchantNotifications = notificationHistory.filter { $0.merchantId == store.merchantId }
        if let lastMerchant = merchantNotifications.sorted(by: { $0.timestamp > $1.timestamp }).first {
            let hoursSince = calendar.dateComponents([.hour], from: lastMerchant.timestamp, to: now).hour ?? 0
            guard hoursSince >= merchantCooldownHours else {
                RTLLog.debug(.notifications, "Blocked: Merchant cooldown active (\(hoursSince)h < \(merchantCooldownHours)h)")
                return false
            }
        }

        // Check merchant weekly limit
        let merchantWeekNotifications = merchantNotifications.filter { $0.timestamp >= weekStart }
        guard merchantWeekNotifications.count < merchantWeeklyLimit else {
            RTLLog.debug(.notifications, "Blocked: Merchant weekly limit reached")
            return false
        }

        // Check merchant monthly limit
        let merchantMonthNotifications = merchantNotifications.filter { $0.timestamp >= monthStart }
        guard merchantMonthNotifications.count < merchantMonthlyLimit else {
            RTLLog.debug(.notifications, "Blocked: Merchant monthly limit reached")
            return false
        }

        return true
    }

    /// Show a notification for the given store
    func showNotification(for store: RTLStore) {
        guard canShowNotification(for: store) else { return }

        let content = UNMutableNotificationContent()
        content.title = store.offerTitle ?? "Offer nearby"
        content.body = store.offerDescription ?? "You're near \(store.name). Tap to view the offer."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )

        notificationCenter.add(request) { error in
            if let error = error {
                RTLLog.error(.notifications, "Notification error: \(error)")
            } else {
                RTLLog.debug(.notifications, "Notification sent for store: \(store.name)")
            }
        }

        // Record notification
        let record = NotificationRecord(storeId: store.id, merchantId: store.merchantId, timestamp: Date())
        notificationHistory.append(record)
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([NotificationRecord].self, from: data) else {
            return
        }

        // Prune old records (30 days)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        notificationHistory = history.filter { $0.timestamp >= cutoff }

        RTLLog.debug(.notifications, "Loaded \(notificationHistory.count) notification records")
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(notificationHistory) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    #if DEBUG
    /// Reset notification history for testing purposes
    func resetHistory() {
        notificationHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: historyKey)
        RTLLog.debug(.notifications, "🧹 Notification history cleared for testing")
    }
    #endif
}

public extension RTLSdk {
    /// Returns foreground presentation options for SDK hyperlocal notifications,
    /// or nil for notifications that should continue through the host's handler.
    static func notificationPresentationOptions(
        for request: UNNotificationRequest
    ) -> UNNotificationPresentationOptions? {
        guard request.identifier.hasPrefix(RTLNotificationManager.identifierPrefix) else { return nil }
        return [.banner, .sound]
    }
}
