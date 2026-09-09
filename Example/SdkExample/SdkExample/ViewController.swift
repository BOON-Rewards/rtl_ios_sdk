import UIKit
import RTLSdk

class ViewController: UIViewController {

    private let statusLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private let loadingOverlay = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var logoutButton: UIBarButtonItem!
    private var rtlWebView: RTLWebView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RTL SDK Example"

        setupUI()
        initializeSDK()
        setupLogoutButton()
    }

    private func setupLogoutButton() {
        logoutButton = UIBarButtonItem(
            title: "Logout",
            style: .plain,
            target: self,
            action: #selector(logoutTapped)
        )
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

        setupLoadingOverlay()
    }

    private func setupLoadingOverlay() {
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.backgroundColor = .systemBackground
        loadingOverlay.isHidden = true
        loadingOverlay.accessibilityViewIsModal = true

        let loadingLabel = UILabel()
        loadingLabel.text = "Loading program…"
        loadingLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [loadingIndicator, loadingLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16

        loadingOverlay.addSubview(stack)
        view.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor)
        ])
    }

    private func initializeSDK() {
        // Initialize the SDK
        RTLSdk.shared.initialize(
            baseURL: URL(string: "https://client-provided-url.example")!,
            urlScheme: "rtlsdkexample",
            delegate: self,
            externalChapterId: nil // Set your chapter ID only if your integration uses chapters.
        )

        // Create webview (the SDK manages its visibility)
        let webView = RTLSdk.shared.createWebView()
        rtlWebView = webView
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
                if !result.success && result.errorCode != "request_cancelled" {
                    statusLabel.text = "Failed to load RTL experience (\(result.errorCode ?? "unknown_error"))"
                    loginButton.isEnabled = true
                }
            }
        }
    }

    @objc private func logoutTapped() {
        RTLSdk.shared.logout()
        RTLSdk.shared.disableLocationFeatures()
        rtlWebView?.isHidden = true
        setLoading(false)
        navigationItem.rightBarButtonItem = nil
        statusLabel.isHidden = false
        statusLabel.text = "Tap Login to continue"
        loginButton.isHidden = false
        loginButton.isEnabled = true
    }
}

// MARK: - RTLSdkDelegate

extension ViewController: RTLSdkDelegate {
    func onReady() {
        print("RTL app is ready")
        statusLabel.isHidden = true
        loginButton.isHidden = true
        navigationItem.rightBarButtonItem = logoutButton

        RTLSdk.shared.enableLocationFeatures()

        #if DEBUG
        RTLSdk.shared.resetNotificationHistory()
        #endif
    }

    func onLoadingStateChanged(isLoading: Bool) {
        setLoading(isLoading)
    }

    func provideAuthToken() async -> String? {
        print("SDK requesting token...")
        // TODO: Fetch a fresh JWT from your backend. Never embed credentials in the app.
        return nil
    }

    // Optional location callbacks
    func onLocationPermissionChange(granted: Bool) {
        print("Location permission changed: \(granted)")
    }

    func onGeofenceEnter(store: RTLStore) {
        print("Entered geofence for store: \(store.name)")
    }
}

private extension ViewController {
    func setLoading(_ isLoading: Bool) {
        if isLoading {
            view.bringSubviewToFront(loadingOverlay)
            loadingOverlay.isHidden = false
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            loadingOverlay.isHidden = true
        }
    }
}
