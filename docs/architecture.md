# Architecture

```
┌──────────────── Social Rewind (SwiftUI app) ────────────────┐
│ Onboarding · Platform settings · Stats                       │
│                                                              │
│ PlatformBrowser (one WKWebView per platform)                 │
│  ├─ WKWebsiteDataStore(forIdentifier:)   isolated cookies    │
│  ├─ WKContentRuleList                    native blocking     │
│  ├─ NavigationPolicy                     host allowlist      │
│  ├─ WKUserScript @ documentStart         filter engine       │
│  │     config: settings + rule pack (JSON)                   │
│  └─ Native chrome: post counter, scroll reminders, grayscale │
│                                                              │
│ App Group storage: settings, app tokens, local stats         │
└──────────────────────────────────────────────────────────────┘
 Extensions: ShieldConfiguration · ShieldAction · DeviceActivityMonitor
```

## Locking the native app

- The user authorizes with `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
- During onboarding the user picks each platform's app in `FamilyActivityPicker`. The tokens we get back are opaque (we can't see bundle IDs), so we store `platform → ApplicationToken` based on the step the user was on.
- `ManagedSettingsStore().shield.applications` holds every token of a platform the user has locked.
- **ShieldConfiguration** extension: a custom shield screen ("Open with Social Rewind").
- **ShieldAction** extension: it can't open our app directly. It posts a local notification that deep-links to `socialrewind://open/<platform>`. *(Spike 0.4 verifies this.)*
- **DeviceActivityMonitor**: reserved for sleep mode and time limits.

## Filter engine (`engine/`)

One JS bundle, injected at document start into the page content world, because it has to wrap `fetch` and `history` before the site's own code runs. Native passes it `window.__SOCIAL_REWIND_CONFIG__ = { settings, rules, platform, debug }` in a preceding user script.

| Layer | Module | Purpose |
|---|---|---|
| Router guard | `core/router.ts` | Wraps `pushState`/`replaceState` and listens for `popstate`/`click`, enforcing route rules (block/redirect) and mode allowlists. |
| Network filter | `core/network.ts` | Wraps `fetch`/`XMLHttpRequest`. For URLs that match, it parses the JSON and drops array items matching declarative predicates (ads, suggested, reels) before the app renders them. |
| DOM filter | `core/dom.ts` | Injected CSS for static selectors, plus a `MutationObserver` for rules that need logic: `hideClosest`, `hideIfText`. |
| Counter | `core/counter.ts` | `IntersectionObserver` that counts each unique post once it has been ≥50% visible for 1s. |
| Bridge | `core/bridge.ts` | Sends `postsViewed`, `routeBlocked`, `ruleHit` (debug) and `ready` events to native through `webkit.messageHandlers.socialRewind` (Android: `SocialRewindAndroid`). |

The engine applies only the rules whose `features` are turned on in settings, or rules belonging to the active `mode`.

## Rule packs (`rules/`)

Rule packs are declarative JSON, validated by `rules/schema/rule-pack.schema.json`. Each pack has a `version` and a `minEngineVersion`. A refreshed pack is used only if it parses, passes validation, has a compatible `minEngineVersion` and a newer `version` than the bundled one. Otherwise the app keeps using the bundled pack.

Packs **can't** add hosts, run script or change native behavior. That keeps rule refresh App Store-safe and limits the damage if the repository is ever compromised. (Planned hardening: ed25519-signed packs; see roadmap.)

## Swift layout

- `ios/Packages/RewindCore`: pure Swift with no UIKit or FamilyControls. Settings model, rule-pack decoding and version checks, host allowlist, and the builder for the injected config script. Unit-tested with `swift test`.
- `ios/SocialRewind`: the SwiftUI app. Glue code around WebKit, FamilyControls and ManagedSettings.
- `ios/Extensions/*`: the Screen Time extensions, which share settings through the App Group `group.app.socialrewind`.
