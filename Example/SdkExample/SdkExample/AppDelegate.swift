import UIKit
import UserNotifications
import RTLSdk

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    private let rtlActionType = "rtlSdk"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = ViewController()
        window?.rootViewController = UINavigationController(rootViewController: viewController)
        window?.makeKeyAndVisible()
        UNUserNotificationCenter.current().delegate = self

        if let deepLinkURL = launchOptions?[.url] as? URL {
            viewController.loadViewIfNeeded()
            _ = RTLSdk.shared.handleDeepLink(deepLinkURL)
        }

        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let rtlEventId = parseRTLPushEventId(from: remoteNotification) {
            viewController.loadViewIfNeeded()
            viewController.presentRTLExperience(
                rtlEventId: rtlEventId,
                statusMessage: "Opening RTL experience from push..."
            )
        }

        return true
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard let navigationController = window?.rootViewController as? UINavigationController,
              let viewController = navigationController.viewControllers.first as? ViewController else {
            return false
        }

        viewController.loadViewIfNeeded()
        return RTLSdk.shared.handleDeepLink(url)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let navigationController = window?.rootViewController as? UINavigationController,
           let viewController = navigationController.viewControllers.first as? ViewController,
           let rtlEventId = parseRTLPushEventId(from: response.notification.request.content.userInfo) {
            viewController.loadViewIfNeeded()
            viewController.presentRTLExperience(
                rtlEventId: rtlEventId,
                statusMessage: "Opening RTL experience from push..."
            )
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let options = RTLSdk.notificationPresentationOptions(for: notification.request) {
            completionHandler(options)
            return
        }
        // Apply the host app's presentation policy to other notifications.
        completionHandler([])
    }

    private func parseRTLPushEventId(from userInfo: [AnyHashable: Any]) -> String? {
        if let actionType = userInfo["rtlActionType"] as? String,
           actionType == rtlActionType,
           let rtlEventId = userInfo["rtlEventId"] as? String,
           !rtlEventId.isEmpty {
            return rtlEventId
        }

        if let metadata = userInfo["metadata"] as? [AnyHashable: Any],
           let actionType = metadata["rtlActionType"] as? String,
           actionType == rtlActionType,
           let rtlEventId = metadata["rtlEventId"] as? String,
           !rtlEventId.isEmpty {
            return rtlEventId
        }

        return nil
    }
}
