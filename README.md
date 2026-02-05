# RTL SDK for iOS

Native iOS SDK for integrating the RTL (Rewards, Transactions, Loyalty) experience into your iOS application.

## Requirements

- iOS 13.0+
- Swift 5.7+
- Xcode 14.0+

## Installation

### Swift Package Manager

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/BOON-Rewards/rtl_ios_sdk.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File > Add Packages...
2. Enter the repository URL: `https://github.com/BOON-Rewards/rtl_ios_sdk.git`
3. Select the version and add to your target

## Quick Start

```swift
import RTLSdk

class MyViewController: UIViewController, RTLSdkDelegate {

    private var rtlWebView: RTLWebView?

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Initialize SDK
        RTLSdk.shared.initialize(
            program: "your-program-id",
            environment: .staging,
            urlScheme: "your-app-scheme"
        )

        // 2. Set delegate BEFORE creating webview
        RTLSdk.shared.delegate = self

        // 3. Create and add webview
        let webView = RTLSdk.shared.createWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        rtlWebView = webView
    }

    func onLoginButtonTapped() {
        Task {
            // 4. Request token and login
            let success = await RTLSdk.shared.requestTokenAndLogin()
            print(success ? "Login successful!" : "Login failed")
        }
    }

    // MARK: - RTLSdkDelegate

    func rtlSdkNeedsToken() async -> String? {
        // Return JWT token from your auth system
        return await MyAuthService.getToken()
    }

    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {
        print("Authenticated!")
    }
}
```

## Integration Guide

### Step 1: Initialize the SDK

Initialize the SDK early in your app's lifecycle, typically in `viewDidLoad` or `AppDelegate`:

```swift
RTLSdk.shared.initialize(
    program: "your-program-id",    // Your RTL program identifier
    environment: .staging,          // .staging or .production
    urlScheme: "your-app-scheme"   // Your app's URL scheme for deep linking
)
```

### Step 2: Set the Delegate

Set the delegate **before** creating the webview. This is important because the SDK may immediately request a token.

```swift
RTLSdk.shared.delegate = self
```

### Step 3: Create the WebView

Create the RTL webview and add it to your view hierarchy:

```swift
let rtlWebView = RTLSdk.shared.createWebView()
rtlWebView.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(rtlWebView)

// Full screen constraints
NSLayoutConstraint.activate([
    rtlWebView.topAnchor.constraint(equalTo: view.topAnchor),
    rtlWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    rtlWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    rtlWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
])
```

### Step 4: Implement Token Provider

Implement `rtlSdkNeedsToken()` to provide tokens when the SDK needs them:

```swift
func rtlSdkNeedsToken() async -> String? {
    // Fetch token from your authentication service
    do {
        let token = try await MyAuthService.fetchJWTToken()
        return token
    } catch {
        print("Failed to get token: \(error)")
        return nil
    }
}
```

This method is called:
- When you call `requestTokenAndLogin()`
- Automatically when the app returns to foreground after 20+ hours (token refresh)

### Step 5: Trigger Login

When the user is ready to access the RTL experience:

```swift
Task {
    let success = await RTLSdk.shared.requestTokenAndLogin()
    if success {
        // Show the webview, hide login UI
    } else {
        // Handle login failure
    }
}
```

## API Reference

### RTLSdk

The main SDK singleton.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `shared` | `RTLSdk` | Singleton instance |
| `delegate` | `RTLSdkDelegate?` | Delegate for receiving SDK events |

#### Methods

##### `initialize(program:environment:urlScheme:)`
Initialize the SDK with configuration. Must be called before any other SDK methods.

```swift
func initialize(program: String, environment: RTLEnvironment, urlScheme: String)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `program` | `String` | Your RTL program identifier (e.g., "crowdplay") |
| `environment` | `RTLEnvironment` | `.staging` or `.production` |
| `urlScheme` | `String` | Your app's URL scheme for deep linking |

##### `createWebView()`
Creates and returns an RTL webview to embed in your view hierarchy.

```swift
func createWebView() -> RTLWebView
```

##### `requestTokenAndLogin()`
Requests a token from the delegate and performs login. This is the recommended way to initiate login.

```swift
@MainActor
func requestTokenAndLogin() async -> Bool
```

**Returns:** `true` if login succeeded, `false` if failed or no token provided.

##### `login(token:)`
Performs login with a provided JWT token. Consider using `requestTokenAndLogin()` instead.

```swift
@MainActor
func login(token: String) async -> Bool
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `token` | `String` | JWT token from your authentication system |

**Returns:** `true` if login succeeded (userAuth received), `false` if failed/timed out (30 seconds).

##### `logout()`
Triggers logout in the webview.

```swift
func logout()
```

##### `registerPushToken(_:type:)`
Registers a push notification token with the RTL backend.

```swift
func registerPushToken(_ token: String, type: RTLTokenType)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `token` | `String` | The device push token |
| `type` | `RTLTokenType` | `.apns` or `.fcm` |

##### `isLoggedIn()`
Returns the current login state.

```swift
func isLoggedIn() -> Bool?
```

**Returns:** `true` if logged in, `false` if not logged in, `nil` if SDK not initialized.

### RTLSdkDelegate

Protocol for receiving SDK events. All methods have default empty implementations.

```swift
public protocol RTLSdkDelegate: AnyObject {

    /// Called when SDK needs a token (initial login or refresh)
    func rtlSdkNeedsToken() async -> String?

    /// Called when authentication succeeds
    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String)

    /// Called when user logs out
    func rtlSdkDidLogout()

    /// Called when RTL requests to open a URL
    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool)

    /// Called when RTL web app is ready
    func rtlSdkDidBecomeReady()
}
```

#### Delegate Methods

| Method | Description |
|--------|-------------|
| `rtlSdkNeedsToken()` | **Required for login.** Return a JWT token or `nil` if unavailable. |
| `rtlSdkDidAuthenticate(accessToken:refreshToken:)` | Called when user successfully authenticates. |
| `rtlSdkDidLogout()` | Called when user logs out. |
| `rtlSdkRequestsOpenUrl(url:forceExternal:)` | Called when RTL requests to open a URL. Open in Safari if `forceExternal` is true. |
| `rtlSdkDidBecomeReady()` | Called when the RTL web app has finished loading. |

### RTLEnvironment

Environment configuration enum.

| Case | Domain Pattern |
|------|----------------|
| `.staging` | `{program}.staging.getboon.com` |
| `.production` | `{program}.prod.getboon.com` |

### RTLTokenType

Push notification token type enum.

| Case | Value | Description |
|------|-------|-------------|
| `.apns` | `"apns"` | Apple Push Notification Service |
| `.fcm` | `"fcm"` | Firebase Cloud Messaging |

### RTLWebView

Embeddable webview for the RTL experience.

#### Methods

| Method | Description |
|--------|-------------|
| `reload()` | Reload the current page |
| `goBack()` | Navigate back in history |
| `goForward()` | Navigate forward in history |
| `canGoBack` | Check if can go back |
| `canGoForward` | Check if can go forward |

## Token Management

The SDK automatically manages token expiration:

- Tokens are considered valid for **20 hours**
- When the app returns to foreground after 20+ hours, the SDK automatically calls `rtlSdkNeedsToken()` to get a fresh token
- The webview is automatically reloaded with the new token

This ensures users always have a valid session without manual intervention.

## Handling External URLs

When the RTL web app needs to open an external URL, implement `rtlSdkRequestsOpenUrl`:

```swift
func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {
    if forceExternal {
        // Must open in Safari
        UIApplication.shared.open(url)
    } else {
        // Can use in-app browser (SFSafariViewController) or Safari
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }
}
```

## Example Implementation

See the `Example/RTLSdkExample` directory for a complete example showing:
- SDK initialization
- Login flow with token callback
- Full-screen webview presentation
- Delegate implementation

To run the example:
```bash
cd Example/RTLSdkExample
open RTLSdkExample.xcodeproj
```

## Troubleshooting

### WebView shows blank screen
- Ensure you've called `initialize()` before `createWebView()`
- Verify `rtlSdkNeedsToken()` returns a valid token
- Check the console for `[RTLSdk]` logs

### Login times out
- Login has a 30-second timeout
- Ensure the JWT token is valid and not expired
- Check network connectivity

### Token refresh not working
- Ensure the delegate is set and `rtlSdkNeedsToken()` is implemented
- Token refresh only triggers after 20+ hours in background

## License

Copyright (c) 2024 Affina Loyalty. All rights reserved.

This SDK is provided under a proprietary license. Use of this SDK requires a valid business agreement with Affina Loyalty. Unauthorized copying, modification, distribution, or use of this software is strictly prohibited.
