# CurrencyPal

Privacy-first, offline-first currency converter for iOS. No accounts, no tracking, no cloud.

## Features

- Instant currency conversion (sub-100ms, on-device)
- Offline mode with cached ECB rates
- Home screen widget (WidgetKit)
- 10 popular currencies (Pro: 165+)
- Beautiful SwiftUI interface
- Zero signup required

## Prerequisites

- Xcode 16+
- iOS 17+ deployment target
- Apple Developer account (for App Store / TestFlight)

## Setup

1. Open Xcode → File → New → Project → iOS App
2. Copy `CurrencyPal/` source files into the project
3. Add SwiftLint via SPM: `https://github.com/realm/SwiftLint`
4. Add PostHog via SPM: `https://github.com/PostHog/posthog-ios`
5. Build & Run (Cmd+R)

## Architecture

```
MVVM + SwiftData + Frankfurter API

Views → ViewModels → Services → Frankfurter API
                  → SwiftData (local cache)
```

## API

Exchange rates from [Frankfurter](https://frankfurter.dev) (ECB data, free, no API key).

## Tech Stack

- Swift 6 / SwiftUI / iOS 17+
- SwiftData (local persistence)
- WidgetKit (home screen widgets)
- StoreKit 2 (subscriptions)
- PostHog (privacy-respecting analytics)

## License

Proprietary. All rights reserved.
