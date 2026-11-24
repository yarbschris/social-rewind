# Roadmap

Legend: ✅ done · 🚧 in progress · ⬜ not started · ❓ needs a decision or verification on a real device

## Phase 0: Spikes (verify on a real device)
- ⬜ 0.1 Request the Family Controls (Distribution) entitlement from Apple. *Owner action, can take weeks.*
- ❓ 0.2 Instagram mobile web in `WKWebView`: login persists across launches; feed, DMs, stories and saved posts all work.
- ❓ 0.3 Network filter: confirm feed data comes through `fetch`/XHR JSON we can rewrite, and record the real response shapes (scrubbed) in `docs/spikes/instagram-network.md`. Also check whether the first feed page arrives server-rendered in the HTML.
- ❓ 0.4 Shield → notification → `socialrewind://` deep-link handoff works.
- ❓ 0.5 Does `shield.webDomains` / the web content filter for instagram.com (which would stop Safari bypass) also block our own `WKWebView`?
- ❓ 0.6 Which Instagram features appear on mobile web at all: reposts, AI info labels, story ads.

## Phase 1: Instagram MVP
- ✅ Repository, license, docs
- 🚧 Filter engine core: router guard, DOM filter, network filter, counter, bridge
- 🚧 Instagram rule pack v0 (selectors **unverified** until spikes 0.2/0.3)
- 🚧 RewindCore Swift package: settings, rule packs, allowlist, config builder
- 🚧 iOS app shell: onboarding, settings, browser, grayscale, counter UI, scroll reminders
- 🚧 Screen Time extensions: shield UI, shield action
- ⬜ App icon and visual design

## Phase 2: Robustness
- ⬜ Filter debug overlay (outline hidden elements and show which rule matched)
- ⬜ Scrubbed fixture capture tool, plus Playwright WebKit tests against fixtures
- ⬜ Optional rule refresh (fetch, validate, version-gate, fall back), plus ed25519 signing
- ⬜ Hard features: story ads, reposts, AI-labeled posts
- ⬜ Localized text matches (non-English UI)

## Phase 3: More platforms (rough order of feasibility)
Reddit → X → LinkedIn → Facebook → Snapchat (web is chat-only; may not work in a mobile web view) → YouTube (Google blocks sign-in inside embedded web views) → TikTok (the web app is mostly the feed we'd be removing)

## Phase 4: Android
No Screen Time equivalent. Options are an AccessibilityService (strict Google Play policy) or UsageStats plus an overlay. The engine and rule packs carry over unchanged.

## Later features
Sleep mode, time limits (DeviceActivity), weekly on-device stats.
