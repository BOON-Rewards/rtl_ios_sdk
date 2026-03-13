import Foundation
import UserNotifications

/// Manages local notifications with rate limiting rules
class RTLNotificationManager: NSObject, UNUserNotificationCenterDelegate {
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

    override init() {
        super.init()
        notificationCenter.delegate = self
        loadHistory()
    }

    /// Request notification permission
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            print("[RTLSdk] Notification permission granted: \(granted)")
            return granted
        } catch {
            print("[RTLSdk] Notification permission error: \(error)")
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
                print("[RTLSdk] Blocked: Outside time window (\(hour):00)")
                return false
            }
        } else {
            print("[RTLSdk] 🔧 Debug mode: bypassing time window check (current hour: \(hour):00)")
        }

        // Check daily limit
        let todayNotifications = notificationHistory.filter { calendar.isDateInToday($0.timestamp) }
        guard todayNotifications.count < dailyLimit else {
            print("[RTLSdk] Blocked: Daily limit reached (\(todayNotifications.count)/\(dailyLimit))")
            return false
        }

        // Check weekly limit
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let weekNotifications = notificationHistory.filter { $0.timestamp >= weekStart }
        guard weekNotifications.count < weeklyLimit else {
            print("[RTLSdk] Blocked: Weekly limit reached")
            return false
        }

        // Check monthly limit
        let monthStart = calendar.date(byAdding: .day, value: -30, to: now)!
        let monthNotifications = notificationHistory.filter { $0.timestamp >= monthStart }
        guard monthNotifications.count < monthlyLimit else {
            print("[RTLSdk] Blocked: Monthly limit reached")
            return false
        }

        // Check merchant cooldown (24 hours)
        let merchantNotifications = notificationHistory.filter { $0.merchantId == store.merchantId }
        if let lastMerchant = merchantNotifications.sorted(by: { $0.timestamp > $1.timestamp }).first {
            let hoursSince = calendar.dateComponents([.hour], from: lastMerchant.timestamp, to: now).hour ?? 0
            guard hoursSince >= merchantCooldownHours else {
                print("[RTLSdk] Blocked: Merchant cooldown active (\(hoursSince)h < \(merchantCooldownHours)h)")
                return false
            }
        }

        // Check merchant weekly limit
        let merchantWeekNotifications = merchantNotifications.filter { $0.timestamp >= weekStart }
        guard merchantWeekNotifications.count < merchantWeeklyLimit else {
            print("[RTLSdk] Blocked: Merchant weekly limit reached")
            return false
        }

        // Check merchant monthly limit
        let merchantMonthNotifications = merchantNotifications.filter { $0.timestamp >= monthStart }
        guard merchantMonthNotifications.count < merchantMonthlyLimit else {
            print("[RTLSdk] Blocked: Merchant monthly limit reached")
            return false
        }

        return true
    }

    /// Show a notification for the given store
    func showNotification(for store: RTLStore) {
        guard canShowNotification(for: store) else { return }

        let content = UNMutableNotificationContent()
        content.title = store.offerTitle ?? "Special Offer Nearby!"
        content.body = store.offerDescription ?? "Check out \(store.name) for exclusive deals"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("[RTLSdk] Notification error: \(error)")
            } else {
                print("[RTLSdk] Notification sent for store: \(store.name)")
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

        print("[RTLSdk] Loaded \(notificationHistory.count) notification records")
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
        print("[RTLSdk] 🧹 Notification history cleared for testing")
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("[RTLSdk] 📬 Presenting notification in foreground: \(notification.request.content.title)")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
