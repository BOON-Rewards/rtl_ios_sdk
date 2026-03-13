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
            urlScheme: "your-app-scheme",
            delegate: self
        )

        // 2. Create and add webview
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

    func onShowExperienceTapped() {
        Task {
            let result = await RTLSdk.shared.presentExperience()
            if !result.success {
                print(result.errorCode ?? "unknown_error")
            }
        }
    }

    // MARK: - RTLSdkDelegate

    func onNeedsToken() async -> String? {
        // Return JWT token from your auth system
        return await MyAuthService.getToken()
    }

    func onLogout() {}
}
```

## Integration Guide

### Step 1: Initialize the SDK

Initialize the SDK early in your app's lifecycle, typically in `viewDidLoad` or `AppDelegate`. Pass the delegate at initialization time to ensure no callbacks are missed:

```swift
RTLSdk.shared.initialize(
    program: "your-program-id",    // Your RTL program identifier
    environment: .staging,          // .staging or .production
    urlScheme: "your-app-scheme",  // Your app's URL scheme for deep linking
    delegate: self                  // Set delegate immediately
)
```

### Step 2: Create the WebView

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

### Step 3: Implement Token Provider

Implement `onNeedsToken()` to provide tokens when the SDK needs them:

> `onNeedsToken()` should call your backend endpoint to fetch a freshly signed JWT. Do not generate or sign JWTs inside the mobile app.

```swift
func onNeedsToken() async -> String? {
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
- When you call `presentExperience()`
- Automatically when the app returns to foreground after 20+ hours (token refresh)

### Step 4: Present the Experience

When the user is ready to access the RTL experience:

```swift
Task {
    let result = await RTLSdk.shared.presentExperience()
    if !result.success {
        // Handle failure by error code, e.g. "token_unavailable"
        print(result.errorCode ?? "unknown_error")
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

##### `initialize(program:environment:urlScheme:delegate:)`
Initialize the SDK with configuration. Must be called before any other SDK methods.

```swift
func initialize(program: String, environment: RTLEnvironment, urlScheme: String, delegate: RTLSdkDelegate?)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `program` | `String` | Your RTL program identifier (e.g., "crowdplay") |
| `environment` | `RTLEnvironment` | `.staging` or `.production` |
| `urlScheme` | `String` | Your app's URL scheme for deep linking |
| `delegate` | `RTLSdkDelegate?` | Delegate for receiving SDK events |

##### `createWebView()`
Creates and returns an RTL webview to embed in your view hierarchy.

```swift
func createWebView() -> RTLWebView
```

##### `presentExperience()`
Requests a token from the delegate, authenticates, and presents the RTL experience.

```swift
func presentExperience() async -> RTLExperienceResult
```

**Returns:** `RTLExperienceResult` with `success == true` on success, or `errorCode` set to a snake_case failure code.

##### `login(token:)`
Performs login with a provided JWT token. Consider using `presentExperience()` instead.

```swift
@MainActor
func login(token: String) async -> RTLExperienceResult
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `token` | `String` | JWT token from your authentication system |

**Returns:** `RTLExperienceResult` with `success == true` if the RTL app finished loading, otherwise `errorCode` explains the failure.

### RTLExperienceResult

Return type for `presentExperience()` and `login(token:)`.

| Property | Type | Description |
|----------|------|-------------|
| `success` | `Bool` | `true` when the experience was presented successfully |
| `errorCode` | `String?` | Snake_case failure code, or `nil` on success |

Known `errorCode` values:
- `token_unavailable`
- `webview_not_created`
- `invalid_token_forward_url`
- `login_timeout`
- `request_cancelled`

##### `logout()`
Triggers logout in the webview.

```swift
func logout()
```

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
    func onNeedsToken() async -> String?

    /// Called when user logs out
    func onLogout()

    /// Called when RTL opens a URL (informational)
    func onOpenUrl(url: URL, forceExternal: Bool)

    /// Called when RTL web app is ready
    func onReady()
}
```

#### Delegate Methods

| Method | Description |
|--------|-------------|
| `onNeedsToken()` | **Required for login.** Return a JWT token or `nil` if unavailable. |
| `onLogout()` | Called when user logs out. |
| `onOpenUrl(url:forceExternal:)` | Called after SDK opens a URL (informational). |
| `onReady()` | Called when the RTL web app has finished loading. |

### RTLEnvironment

Environment configuration enum.

| Case | Domain Pattern |
|------|----------------|
| `.staging` | `{program}.staging.getboon.com` |
| `.production` | `{program}.prod.getboon.com` |

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
- When the app returns to foreground after 20+ hours, the SDK automatically calls `onNeedsToken()` to get a fresh token
- The webview is automatically reloaded with the new token
- The SDK keeps the webview hidden until `presentExperience()` succeeds, and hides it again on logout

This ensures users always have a valid session without manual intervention.

### JWT Token Structure

The JWT token provided to the SDK should contain the following structure:

```json
{
  "user": {
    "id": "2b030a36-ad21-1222-1232-c5bf898d17b1",
    "gender": "Female",
    "firstName": "Ericka",
    "lastName": "N",
    "email": "user@example.com"
  },
  "orgId": "ckp9n3d8y0063ksuvchc6wfgt",
  "chapterId": "c32047b4-5d99-4505-b733-71f1fde4e570",
  "pointsPerDollar": 200,
  "iat": 1754307084,
  "exp": 1754307144
}
```

| Field | Description |
|-------|-------------|
| `user.id` | Unique user identifier |
| `user.gender` | User's gender |
| `user.firstName` | User's first name |
| `user.lastName` | User's last name |
| `user.email` | User's email address |
| `orgId` | Organization identifier |
| `chapterId` | Chapter identifier |
| `pointsPerDollar` | Points earned per dollar spent |
| `iat` | Issued at timestamp (Unix) |
| `exp` | Expiration timestamp (Unix) |

### Best Practices

- **Set JWT expiry to 1 minute**: For security, generate tokens with a short expiry time (60 seconds). The SDK will request a fresh token via `onNeedsToken()` when needed.
- Generate tokens server-side only - never expose your signing secret in the mobile app
- Always validate user identity before generating tokens

## Location-Based Notifications

The SDK provides built-in support for geolocation-based notifications. When enabled, the SDK will:
- Request location permissions from the user
- Track location changes in the background
- Fetch nearby stores from the RTL API
- Set up geofences around stores (100m radius)
- Show local notifications when user enters a store geofence

### Enabling Location Features

After login, enable location features:

```swift
// In your login success handler
RTLSdk.shared.enableLocationFeatures()
```

The SDK handles all permission requests internally. No additional setup is required in your view controller.

### Location API Reference

#### Methods

##### `enableLocationFeatures()`
Enables location-based notifications. Requests permissions and sets up geofencing.

```swift
func enableLocationFeatures()
```

##### `disableLocationFeatures()`
Disables location-based notifications and stops all monitoring.

```swift
func disableLocationFeatures()
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isLocationFeaturesEnabled` | `Bool` | Whether location features are currently enabled |
| `hasLocationPermission` | `Bool` | Whether background location permission is granted |

### Optional Location Delegate Methods

You can optionally implement these delegate methods to receive location-related callbacks:

```swift
extension MyViewController: RTLSdkDelegate {
    // Called when location permission status changes
    func onLocationPermissionChange(granted: Bool) {
        print("Location permission: \(granted)")
    }

    // Called when user enters a store geofence
    func onGeofenceEnter(store: RTLStore) {
        print("Entered geofence for: \(store.name)")
    }
}
```

### RTLStore

Data model for stores returned in geofence callbacks:

```swift
public struct RTLStore {
    public let id: String
    public let name: String
    public let merchantId: String
    public let latitude: Double
    public let longitude: Double
    public let offerTitle: String?
    public let offerDescription: String?
}
```

### Notification Rate Limiting

The SDK applies intelligent rate limiting to notifications:

| Rule | Value |
|------|-------|
| Daily limit | 2 notifications |
| Weekly limit | 7 notifications |
| Monthly limit | 20 notifications |
| Merchant cooldown | 24 hours between same merchant |
| Time window | 10:00 AM - 8:00 PM only |

### Required Info.plist Entries

Add these entries to your app's Info.plist:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to show you nearby offers.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>We need background location access to notify you of nearby offers.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show you nearby offers.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

## Handling External URLs

The SDK automatically handles all URL requests:
- **In-app browser** (`forceExternal: false`): Opens in `SFSafariViewController`
- **External browser** (`forceExternal: true`): Opens in Safari

The delegate callback is informational - you can use it for logging or analytics:

```swift
func onOpenUrl(url: URL, forceExternal: Bool) {
    // Optional: Log for analytics
    Analytics.log("URL opened", properties: ["url": url.absoluteString, "external": forceExternal])
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
- Verify `onNeedsToken()` returns a valid token
- Check the console for `[RTLSdk]` logs

### Login times out
- Login has a 30-second timeout
- Ensure the JWT token is valid and not expired
- Check network connectivity

### Token refresh not working
- Ensure the delegate is set and `onNeedsToken()` is implemented
- Token refresh only triggers after 20+ hours in background
