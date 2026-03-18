import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    private let appScheme = "rtlsdkexample"
    private let rtlDeepLinkHost = "rtlsdk"
    private let rtlActionType = "rtlSdk"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = ViewController()
        window?.rootViewController = UINavigationController(rootViewController: viewController)
        window?.makeKeyAndVisible()
        UNUserNotificationCenter.current().delegate = self

        if let deepLinkUrl = launchOptions?[.url] as? URL,
           let deepLinkContext = parseRTLDeepLink(from: deepLinkUrl) {
            viewController.loadViewIfNeeded()
            viewController.presentRTLExperience(
                rtlEventId: deepLinkContext.rtlEventId,
                rtlRedirectUrl: deepLinkContext.rtlRedirectUrl
            )
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
              let viewController = navigationController.viewControllers.first as? ViewController,
              let deepLinkContext = parseRTLDeepLink(from: url) else {
            return false
        }

        viewController.loadViewIfNeeded()
        viewController.presentRTLExperience(
            rtlEventId: deepLinkContext.rtlEventId,
            rtlRedirectUrl: deepLinkContext.rtlRedirectUrl
        )
        return true
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

    private func parseRTLDeepLink(from url: URL) -> (rtlEventId: String?, rtlRedirectUrl: String?)? {
        guard url.scheme?.lowercased() == appScheme,
              url.host?.lowercased() == rtlDeepLinkHost else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rtlEventId = components?.queryItems?.first(where: { $0.name == "rtlEventId" })?.value
        let rtlRedirectUrl = components?.queryItems?.first(where: { $0.name == "rtlRedirectUrl" })?.value
        return (rtlEventId, rtlRedirectUrl)
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
