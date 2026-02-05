# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the SDK
swift build

# Clean build
swift package clean && swift build

# Resolve dependencies (if needed)
swift package resolve
```

## Project Overview

RTL iOS SDK is a Swift-based mobile SDK for integrating the RTL (Rewards, Transactions, Loyalty) platform into iOS applications. It provides a WKWebView-based interface with a JavaScript bridge for native-web communication.

**Requirements:** iOS 13.0+, Swift 5.7+, Xcode 14.0+

**Build System:** Swift Package Manager (SPM) - no external dependencies

## Architecture

### Core Components

- **RTLSdk** (`Sources/RTLSdk/RTLSdk.swift`) - Main singleton entry point. Handles configuration, async login flow with 30-second timeout, and coordinates between webview and delegate.

- **RTLWebView** (`Sources/RTLSdk/RTLWebView.swift`) - WKWebView wrapper that embeds as a UIView. Configures web inspector (DEBUG only), inline media playback, and URL whitelisting for `getboon.com` and `affinaloyalty.com` domains.

- **RTLMessageHandler** (`Sources/RTLSdk/RTLMessageHandler.swift`) - JavaScript bridge using `WKScriptMessageHandler`. Handler name is `inappwebview`. Processes messages: `openExternalUrl`, `userAuth`, `userLogout`, `appReady`.

- **RTLSdkDelegate** (`Sources/RTLSdk/RTLSdkDelegate.swift`) - Protocol for receiving SDK events (authentication, logout, URL open requests, ready state).

### Data Flow

1. Host app calls `RTLSdk.shared.initialize()` with program ID, environment, and URL scheme
2. `createWebView()` returns an `RTLWebView` that loads the RTL platform
3. JavaScript in webview sends messages to `inappwebview` handler
4. `RTLMessageHandler` parses messages and calls back to `RTLSdk`
5. `RTLSdk` forwards events to the delegate

### Environment Configuration

- `RTLEnvironment.staging` → `*.staging.getboon.com`
- `RTLEnvironment.production` → `*.prod.getboon.com`

## Example App

The example app is at `Example/RTLSdkExample/`. Open the `.xcodeproj` in Xcode to run it. It demonstrates SDK initialization, webview embedding, async login, and delegate handling.
