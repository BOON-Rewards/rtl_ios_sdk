import UIKit
import RTLSdk

class ViewController: UIViewController {

    private var rtlWebView: RTLWebView?
    private let statusLabel = UILabel()
    private let loginButton = UIButton(type: .system)

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
        statusLabel.text = "SDK Status: Not initialized"
        view.addSubview(statusLabel)

        // Login button
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        loginButton.setTitle("Login with Test Token", for: .normal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        view.addSubview(loginButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
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
            urlScheme: "rtlsdkexample"
        )

        // Set delegate
        RTLSdk.shared.delegate = self

        // Create and embed the webview
        let webView = RTLSdk.shared.createWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 20),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.rtlWebView = webView
        updateStatus()
    }

    @objc private func loginTapped() {
        // In a real app, you would get this token from your authentication system
        let testToken = "your-jwt-token-here"

        statusLabel.text = "Logging in..."
        loginButton.isEnabled = false

        Task {
            let success = await RTLSdk.shared.login(token: testToken)

            await MainActor.run {
                if success {
                    statusLabel.text = "Login successful!"
                } else {
                    statusLabel.text = "Login failed or timed out"
                }
                loginButton.isEnabled = true
                updateStatus()
            }
        }
    }

    private func updateStatus() {
        let isLoggedIn = RTLSdk.shared.isLoggedIn()
        let statusText: String
        switch isLoggedIn {
        case .some(true):
            statusText = "Logged In"
        case .some(false):
            statusText = "Not Logged In"
        case .none:
            statusText = "Not Initialized"
        }
        statusLabel.text = "SDK Status: \(statusText)"
    }
}

// MARK: - RTLSdkDelegate

extension ViewController: RTLSdkDelegate {

    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {
        print("Authenticated! Access token: \(accessToken.prefix(20))...")
        updateStatus()
    }

    func rtlSdkDidLogout() {
        print("User logged out")
        updateStatus()
    }

    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {
        print("Open URL requested: \(url), forceExternal: \(forceExternal)")
        if forceExternal {
            UIApplication.shared.open(url)
        } else {
            // Could present in-app browser here
            UIApplication.shared.open(url)
        }
    }

    func rtlSdkDidBecomeReady() {
        print("RTL app is ready")
    }
}
