# CLAUDE.md — CurrencyPal

## Overview

**CurrencyPal** is a privacy-first, offline-first currency converter for iOS. No accounts, no tracking, no cloud. Exchange rates cached on-device via SwiftData, conversion math runs locally. Widget-first UX for glanceable rates.

**Problem:** Travelers waste time on daily "math tax" while existing converters bombard with ads, require accounts, and break offline.

**Stack:** iOS 17+ / Swift 6 / SwiftUI / SwiftData / WidgetKit / StoreKit 2

## Directory Structure

```
CurrencyPal/
├── CurrencyPalApp.swift      # App entry point, ModelContainer setup
├── ContentView.swift          # Root view
├── Models/                    # Domain models (SOURCE OF TRUTH)
│   ├── Currency.swift         # CurrencyCode enum + ExchangeRate @Model + FavoritePair @Model
│   └── FrankfurterResponse.swift  # API response Codable
├── Views/                     # SwiftUI views
│   ├── ConverterView.swift    # Main converter screen
│   ├── CurrencyInputCard.swift # Input/result cards
│   └── FreshnessBadge.swift   # Rate freshness indicator
├── ViewModels/                # MVVM view models
│   └── ConverterViewModel.swift # Conversion logic, cache management
├── Services/                  # Network + business logic
│   └── ExchangeRateService.swift # Frankfurter API + SwiftData cache
└── Widgets/                   # WidgetKit extension (TODO: v1.1)
CurrencyPalTests/
└── ConverterTests.swift       # Swift Testing (@Test)
docs/
└── prd.md                     # Product Requirements Document
```

## Common Commands

```bash
# Build & Run
# Open CurrencyPal.xcodeproj in Xcode → Cmd+R

# Tests
# Cmd+U in Xcode, or:
# xcodebuild test -scheme CurrencyPal -destination 'platform=iOS Simulator,name=iPhone 16'

# Lint
# SwiftLint runs as Xcode build phase (add via SPM plugin)
```

## Domain Models (Read These First)

**Always start here before writing any code.**

- `Models/Currency.swift` — `CurrencyCode` enum (10 currencies, flags, symbols), `ExchangeRate` @Model (cache), `FavoritePair` @Model
- `Models/FrankfurterResponse.swift` — API response shape

These models are the single source of truth. All views, view models, and services depend on them.

## Architecture

- **MVVM** — Views observe ViewModels via @Observable, ViewModels use Services
- **SwiftData** — @Model for persistence, ModelContainer at app level, ModelContext injected via @Environment
- **Offline-first** — Rates cached in SwiftData, refreshed when stale (>4h) or on manual pull
- **Privacy-first** — Zero network calls except Frankfurter API for rates. No analytics PII. No accounts.

## API

- **Frankfurter** (frankfurter.dev) — ECB rates, free, no API key, unlimited
- Endpoint: `GET https://api.frankfurter.dev/v1/latest?base=USD`
- Returns all rates in single call, cache locally

## Key Decisions

- No CloudKit/Firebase — local only, privacy-first
- No SuperDuperAiAuth — no accounts needed for a converter
- Frankfurter over paid APIs — free, institutional (ECB), sufficient for daily rates
- 10 currencies in free tier — USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, RUB, TRY
- StoreKit 2 SubscriptionStoreView for paywall

## Don't

- Don't add cloud sync or accounts
- Don't use UIKit (SwiftUI only)
- Don't add currencies beyond the 10 free-tier ones without Pro gate
- Don't make network calls for anything other than exchange rates
- Don't collect or store any user personal data

## Do

- Do read Models/ first before any changes
- Do keep all conversion math on-device
- Do show rate freshness badge (green = fresh, orange = stale)
- Do use Swift Testing (@Test) for new tests
- Do use async/await for all async work
- Do use String Catalog (.xcstrings) for any user-facing strings
