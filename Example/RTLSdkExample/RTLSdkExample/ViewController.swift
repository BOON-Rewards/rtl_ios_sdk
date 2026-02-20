import UIKit
import RTLSdk

class ViewController: UIViewController {

    private var rtlWebView: RTLWebView?
    private let statusLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private var webViewTopConstraint: NSLayoutConstraint?

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
            externalChapterId: "c32047b4-5d99-4505-b733-71f1fde4e570"
        )

        // Set delegate
        RTLSdk.shared.delegate = self

        // Create webview (hidden until login)
        let webView = RTLSdk.shared.createWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        view.addSubview(webView)

        // Full screen constraints
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.rtlWebView = webView
    }

    @objc private func loginTapped() {
        loginButton.isEnabled = false
        statusLabel.text = "Logging in..."

        Task {
            _ = await RTLSdk.shared.requestTokenAndLogin()

            await MainActor.run {
                // Show full screen webview regardless of login result
                // (web app handles its own auth state)
                showFullScreenWebView()

                // Enable location features (SDK handles permissions internally)
                RTLSdk.shared.enableLocationFeatures()

                #if DEBUG
                // Reset notification history for testing geofence notifications
                RTLSdk.shared.resetNotificationHistory()
                #endif
            }
        }
    }

    private func showFullScreenWebView() {
        // Hide login UI
        statusLabel.isHidden = true
        loginButton.isHidden = true

        // Show webview full screen
        rtlWebView?.isHidden = false

        // Hide navigation bar for true full screen
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
}

// MARK: - RTLSdkDelegate

extension ViewController: RTLSdkDelegate {

    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {
        print("Authenticated! Access token: \(accessToken.prefix(20))...")
    }

    func rtlSdkDidLogout() {
        print("User logged out")
        // Show login UI again
        rtlWebView?.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = "Session ended. Tap Login to continue"
        loginButton.isHidden = false
        loginButton.isEnabled = true
        navigationController?.setNavigationBarHidden(false, animated: true)
    }

    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {
        print("Open URL requested: \(url), forceExternal: \(forceExternal)")
        UIApplication.shared.open(url)
    }

    func rtlSdkDidBecomeReady() {
        print("RTL app is ready")
    }

    func rtlSdkNeedsToken() async -> String? {
        print("SDK requesting token...")
        // In a real app, call your auth service here
        return testToken
    }

    // Optional location callbacks
    func rtlSdkLocationPermissionDidChange(granted: Bool) {
        print("Location permission changed: \(granted)")
    }

    func rtlSdkDidEnterGeofence(store: RTLStore) {
        print("Entered geofence for store: \(store.name)")
    }
}
