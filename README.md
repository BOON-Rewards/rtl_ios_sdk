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
    .package(url: "https://github.com/your-org/rtl_sdk_ios.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File > Add Packages...
2. Enter the repository URL
3. Select the version and add to your target

## Usage

### Initialization

Initialize the SDK early in your app's lifecycle (e.g., in `AppDelegate` or `SceneDelegate`):

```swift
import RTLSdk

// Initialize with your configuration
RTLSdk.shared.initialize(
    program: "your-program-id",
    environment: .staging,  // or .production
    urlScheme: "your-app-scheme"
)

// Set delegate to receive events
RTLSdk.shared.delegate = self
```

### Embedding the WebView

Create and embed the RTL webview in your view hierarchy:

```swift
let rtlWebView = RTLSdk.shared.createWebView()
view.addSubview(rtlWebView)

// Add constraints
rtlWebView.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    rtlWebView.topAnchor.constraint(equalTo: view.topAnchor),
    rtlWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    rtlWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    rtlWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
])
```

### Login

Login with a JWT token from your authentication system. The `login` method is async and returns when authentication completes or times out:

```swift
Task {
    let success = await RTLSdk.shared.login(token: jwtToken)
    if success {
        print("Login successful!")
    } else {
        print("Login failed or timed out")
    }
}
```

### Check Login State

```swift
let isLoggedIn = RTLSdk.shared.isLoggedIn()
// Returns: true (logged in), false (not logged in), or nil (not initialized)
```

### Logout

```swift
RTLSdk.shared.logout()
```

### Register Push Token

Register your device's push notification token:

```swift
RTLSdk.shared.registerPushToken(deviceToken, type: .apns)
// or for FCM:
RTLSdk.shared.registerPushToken(fcmToken, type: .fcm)
```

### Delegate

Implement `RTLSdkDelegate` to receive SDK events:

```swift
extension YourViewController: RTLSdkDelegate {
    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {
        // User successfully authenticated
    }

    func rtlSdkDidLogout() {
        // User logged out
    }

    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {
        // RTL requests to open a URL
        if forceExternal {
            UIApplication.shared.open(url)
        } else {
            // Present in-app browser
        }
    }

    func rtlSdkDidBecomeReady() {
        // RTL web app finished loading
    }
}
```

## Environment

The SDK supports two environments:

- `.staging` - Connects to `{program}.staging.getboon.com`
- `.production` - Connects to `{program}.prod.getboon.com`

## Example App

See the `Example/RTLSdkExample` directory for a complete example implementation.

## License

Copyright (c) 2024 Affina Loyalty. All rights reserved.

This SDK is provided under a proprietary license. Use of this SDK requires a valid business agreement with Affina Loyalty. Unauthorized copying, modification, distribution, or use of this software is strictly prohibited.
