---
type: opportunity
status: validated
title: "CurrencyPal — PRD"
created: 2026-02-08
updated: 2026-02-08
tags: [currencypal, prd, ios-swift, privacy, currency, widgets]
opportunity_score: 7.5
evidence_sources: 25
related:
  - 1-methodology/stacks/ios-swift.yaml
  - 1-methodology/dev-principles.md
  - 0-principles/manifest.md
  - 3-opportunities/currencypal/research.md
---

# CurrencyPal — Product Requirements Document

## Problem

Travelers, digital nomads, and expats waste time on daily "math tax" — repeated mental currency conversion — while existing converter apps bombard them with ads, require accounts, collect personal data, and break offline when needed most.

## Target User

**Primary:** International travelers (1.52B trips/year) who need quick currency conversion at shops, restaurants, and ATMs — often without reliable internet.

**Secondary:** Digital nomads (40-80M globally) managing finances across 3-5 currencies daily. Tech-savvy, privacy-conscious, willing to pay for quality tools.

**Tertiary:** Expats (280-304M) comparing costs between home and host country currencies.

**Behavior:** Opens converter 5-15 times/day while traveling. Prefers glancing at a widget over opening an app. Values speed and simplicity over features.

## Market Opportunity

### Market Size (TAM/SAM/SOM)

| Metric | Value | Source |
|--------|-------|--------|
| **TAM** | $217.7B (cross-border payments, 2025) | Allied Market Research |
| **SAM** | $1.5-2.1B (currency converter apps) | Verified Market Reports |
| **SOM** | $5-15M (Year 1, privacy niche) | Estimated |
| **Growth** | 9.5-11.4% CAGR to $3.2-5.9B by 2033 | Market Research Intellect |

### Evidence-Based Pain Points

1. **Privacy invasion:** Apps collect device data, advertising IDs, location, share with ad networks. Forced sign-ups for basic features. (Source: dev.to, IndustryWired)
2. **Ads and bloated UX:** Free apps bombard with ads, premium features locked behind paywalls — "free users can only track 4 currencies." (Source: App Store reviews, AppleInsider)
3. **Poor offline support:** Wise has NO offline mode. XE's offline caching is unreliable. Most apps require internet. (Source: TripAdvisor forums)
4. **Rate confusion:** Mid-market rates differ from actual card rates by 3-5%. No way to input personal card markup. (Source: Rick Steves Forum)
5. **Broken widgets:** XE widget broken since January 2026 — clicks open app instead of allowing edits. (Source: App Store reviews)

### Competitive Analysis

| Competitor | Approach | Gap |
|-----------|----------|-----|
| **XE Currency** | 180+ currencies, transfers, ads in free | Dated UI, ads, sneaky transfer fees, broken widget |
| **Wise** | Mid-market rates, multi-currency card | NO offline, requires account + verification |
| **Revolut** | Neo-bank with 36 currencies | Weekend markup 1%, bloated (banking/stocks/crypto) |
| **Currency Converter Plus** | Paid app, good offline | $2.99, basic features, no widgets |
| **Easy Currency** | 200+ currencies, free | Ad-heavy, basic UI |

**Our gap:** No major app combines privacy-first + offline-first + widget-first + modern UI + zero signup.

---

## Solution

A privacy-first, offline-first currency converter for iOS that works instantly with zero setup. Cache exchange rates on-device, convert with a glance via home screen widgets, and never send personal data anywhere. Beautiful SwiftUI interface optimized for the one thing it does: fast, accurate currency conversion.

### Core Features (MVP)

1. **Instant conversion:** Select two currencies, type amount, see result. Sub-100ms on-device math.
2. **Offline mode:** Full rate table cached locally (SwiftData). Works on planes, in villages, anywhere. Shows "Rates from: [timestamp]" freshness badge.
3. **Home screen widget:** WidgetKit widget showing your favorite currency pair. Glanceable, always fresh via Background App Refresh.
4. **10 popular currencies:** USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, RUB, TRY (Pro unlocks 165+).
5. **Favorites:** Pin your most-used currency pairs for one-tap access.
6. **Rate source:** Frankfurter API (ECB data, free, no API key, institutional source).
7. **Zero signup:** No account, no email, no tracking. Open and use immediately.

### Non-Goals (v1)

- Money transfers (requires financial licensing)
- Crypto conversion (regulatory complexity)
- Historical charts (Pro v2 feature)
- Apple Watch (Pro v2 feature)
- Rate alerts/notifications (Pro v2 feature)
- Multi-currency simultaneous view (Pro v2 feature)

---

## Tech Stack

**Stack:** iOS Swift
**Platform:** iOS 17+
**Language:** Swift 6
**UI Framework:** SwiftUI
**Package Manager:** SPM

**Key Packages:**
- SwiftUI (UI)
- SwiftData (local rate cache, favorites)
- WidgetKit (home screen widgets)
- StoreKit 2 (subscriptions)
- URLSession async/await (API calls)
- PostHog (posthog-ios, privacy-respecting analytics)
- SwiftLint (linter)

**API:**
- Primary: Frankfurter (frankfurter.dev) — free, unlimited, ECB data, no key
- Fallback: ExchangeRate-API (exchangerate-api.com) — 165 currencies, no key

**Stack Notes:**
- SwiftUI only, no UIKit
- Swift 6 concurrency (async/await)
- Local-first: SwiftData, no cloud, no Firebase, no CloudKit
- String Catalog for i18n (.xcstrings) — English first
- SwiftLint as SPM plugin
- Swift Testing (@Test) for new tests
- StoreKit 2 for subscriptions

**Architecture:** MVVM

### Data Flow

```
App Launch → Check rate cache age
  → If stale (>4h): fetch from Frankfurter API → store in SwiftData
  → If fresh: use cached rates
User types amount → on-device multiplication → display result
Widget → reads from shared SwiftData container → displays pair
```

---

## Architecture Principles

### Universal (from dev-principles.md)

SOLID, DRY, KISS, TDD, Clean Architecture, Privacy-First, i18n

Full reference: `1-methodology/dev-principles.md`

### Manifesto Principles (from manifest.md)

- **Privacy isn't a feature. It's architecture.** On-device processing. Local storage. No accounts. If I can't see your data, I can't leak it.
- **Offline-first when possible.** Independence from connectivity. Your tool should work on a plane, in a village, during an outage.
- **One pain → one feature → launch.** One problem (currency math tax), one solution (instant converter), shipped in days.
- **Speed over perfection.** Ship, learn, iterate. The market teaches faster than planning.

---

## Monetization

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0 | 10 currencies, daily rates, 1 basic widget, banner ads |
| **Pro** | $2.99/mo or $19.99/yr | 165+ currencies, no ads, custom widgets, rate alerts, Watch |
| **Lifetime** | $29.99 | All Pro features forever |

Expected conversion: 3-5% free → Pro.

---

## Testing Strategy

**Framework:** Swift Testing (@Test) + XCTest

- [ ] Unit tests: conversion math (rounding, edge cases, zero, large numbers)
- [ ] Unit tests: rate cache freshness logic
- [ ] Integration tests: Frankfurter API response parsing
- [ ] Integration tests: SwiftData persistence
- [ ] Widget tests: shared container data access
- [ ] StoreKit 2 tests: subscription entitlement checks

---

## Deployment

**Platform:** App Store

- [ ] Xcode Cloud CI/CD
- [ ] App Store Connect metadata + screenshots
- [ ] PostHog analytics (EU hosting)
- [ ] ASO: keywords "currency converter offline privacy"
- [ ] Privacy nutrition label (minimal: no data collected)

---

## MVP Timeline (2 weeks)

| Week | Deliverable |
|------|------------|
| **Day 1-3** | Project setup, SwiftData models, Frankfurter API client, conversion logic + tests |
| **Day 4-6** | SwiftUI main screen (converter), favorites, offline cache |
| **Day 7-8** | WidgetKit widget (single pair), shared container |
| **Day 9-10** | StoreKit 2 paywall, banner ads (free tier) |
| **Day 11-12** | Polish UI, i18n setup, SwiftLint, edge cases |
| **Day 13-14** | TestFlight beta, App Store submission |

---

## Success Metrics

| Metric | Target (Month 1) | Target (Month 3) |
|--------|------------------|------------------|
| Downloads | 1,000 | 10,000 |
| DAU/MAU | >30% | >35% |
| Free → Pro conversion | 2% | 3-5% |
| App Store rating | 4.5+ | 4.7+ |
| Crash-free rate | 99.5% | 99.9% |

---

## Launch Checklist

- [ ] MVP features complete (7 core features)
- [ ] Tests passing (unit + integration)
- [ ] TestFlight beta with 5+ testers
- [ ] App Store submission
- [ ] Privacy nutrition label configured
- [ ] ASO keywords optimized
- [ ] PostHog analytics verified
- [ ] Landing page live (optional v1)

---

## ПОТОК Score: 7.5/10

**Key advantage:** Privacy-first + widget-first in a market where no competitor occupies this niche.
**Key risk:** Crowded App Store category, hard to rank organically.
**Asymmetry:** 2 weeks / $0 cost vs $5-15M SOM potential. Excellent risk/reward.

---

*Generated by `make prd` + `/validate-idea` on 2026-02-08*
*Stack: ios-swift | Research: 25 sources | ПОТОК validated*
