import UIKit
import RTLSdk

class ViewController: UIViewController {

    private let statusLabel = UILabel()
    private let loginButton = UIButton(type: .system)

    // Test token - in a real app, this would come from your authentication system
    private let testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjp7ImlkIjoiMmIwMzBhMzYtYWQyMS0xMjIyLTEyMzItYzViZjg5OGQxN2IxIiwiZ2VuZGVyIjoiRmVtYWxlIiwiZmlyc3ROYW1lIjoiRXJpY2thIiwibGFzdE5hbWUiOiJOIiwiZW1haWwiOiJsZXZvbmFsdkBnZXRib29uLmNvbSJ9LCJvcmdJZCI6ImNrcDluM2Q4eTAwNjNrc3V2Y2hjNndmZ3QiLCJjaGFwdGVySWQiOiJjMzIwNDdiNC01ZDk5LTQ1MDUtYjczMy03MWYxZmRlNGU1NzAiLCJwb2ludHNQZXJEb2xsYXIiOjIwMCwiaWF0IjoxNzU0MzA3MDg0LCJleHAiOjE4NDkwMzMwMDJ9.3yTQC0bEeiogdHd4qM_Wh8bRnY_aQ9F9ngk5QUF_CF8"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RTL SDK Example"

        setupUI()
        initializeSDK()
    }

    private func setupUI() {
        // Status label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Tap Login to continue"
        view.addSubview(statusLabel)

        // Login button
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.setTitle("Login", for: .normal)
        loginButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        view.addSubview(loginButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            loginButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func initializeSDK() {
        // Initialize the SDK
        RTLSdk.shared.initialize(
            program: "crowdplay",
            environment: .staging,
            urlScheme: "rtlsdkexample",
            delegate: self,
            externalChapterId: "c32047b4-5d99-4505-b733-71f1fde4e570"
        )

        // Create webview (the SDK manages its visibility)
        let webView = RTLSdk.shared.createWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // Full screen constraints
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

    }

    @objc private func loginTapped() {
        presentRTLExperience(statusMessage: "Logging in...")
    }

    func presentRTLExperience(
        rtlEventId: String? = nil,
        rtlRedirectUrl: String? = nil,
        statusMessage: String = "Opening RTL experience..."
    ) {
        loginButton.isEnabled = false
        statusLabel.text = statusMessage

        Task {
            let result = await RTLSdk.shared.presentExperience(
                rtlEventId: rtlEventId,
                rtlRedirectUrl: rtlRedirectUrl
            )

            await MainActor.run {
                if result.success {
                    statusLabel.isHidden = true
                    loginButton.isHidden = true

                    // Enable location features (SDK handles permissions internally)
                    RTLSdk.shared.enableLocationFeatures()

                    #if DEBUG
                    // Reset notification history for testing geofence notifications
                    RTLSdk.shared.resetNotificationHistory()
                    #endif
                } else {
                    statusLabel.text = "Failed to load RTL experience (\(result.errorCode ?? "unknown_error"))"
                    loginButton.isEnabled = true
                }
            }
        }
    }
}

// MARK: - RTLSdkDelegate

extension ViewController: RTLSdkDelegate {
    func onLogout() {
        print("User logged out")
        statusLabel.isHidden = false
        statusLabel.text = "Session ended. Tap Login to continue"
        loginButton.isHidden = false
        loginButton.isEnabled = true
    }

    func onOpenUrl(url: URL, forceExternal: Bool) {
        print("URL opened: \(url), forceExternal: \(forceExternal)")
        // URL is already opened by SDK - this callback is informational
    }

    func onReady() {
        print("RTL app is ready")
    }

    func onNeedsToken() async -> String? {
        print("SDK requesting token...")
        // In a real app, call your auth service here
        return testToken
    }

    // Optional location callbacks
    func onLocationPermissionChange(granted: Bool) {
        print("Location permission changed: \(granted)")
    }

    func onGeofenceEnter(store: RTLStore) {
        print("Entered geofence for store: \(store.name)")
    }
}
