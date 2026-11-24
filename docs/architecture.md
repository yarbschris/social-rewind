# Architecture

```
┌──────────────── Social Rewind (SwiftUI app) ────────────────┐
│ Onboarding · Platform settings · Stats                       │
│                                                              │
│ PlatformBrowser (one WKWebView per platform)                 │
│  ├─ WKWebsiteDataStore(forIdentifier:)   isolated cookies    │
│  ├─ WKContentRuleList                    native blocking     │
│  ├─ NavigationPolicy                     host allowlist      │
│  ├─ WKUserScript @ documentStart, page world: router+network │
│  ├─ WKUserScript @ documentStart, "SocialRewind" world:      │
│  │     CSS/DOM filter, counter, identity, bridge             │
│  │     (config passed to both by closure)                    │
│  ├─ URL observer (KVO)                   route backstop      │
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

Two bundles, both injected at document start (see [ADR 0004](decisions/0004-two-content-worlds.md)):

- **Page world** (`social-rewind-page.js`): has to share the site's JS globals in order to wrap `history`, `fetch` and `XMLHttpRequest` before the site's code runs. It contains no bridge and defines no globals. Instagram's scripts can tamper with it, but only to weaken their own filtering.
- **Isolated world** (`social-rewind-isolated.js`, `WKContentWorld` "SocialRewind"): CSS/DOM filtering, the counter, identity and the bridge. Page scripts can't see it, and the message handler is registered only in this world.

The two worlds share only the DOM. The page bundle writes `html[data-sr-path]` (for route-scoped CSS) and `html[data-sr-event]` (route-blocked and error events, which the isolated bundle sanitizes and forwards).

Native wraps each bundle as `(function(){ const __SR_CONFIG__ = {...}; <bundle> })()`, so the config (settings, rule pack, username) is never a global the page can read.

| Layer | Module | World | Purpose |
|---|---|---|---|
| Router guard | `core/router.ts` | page | Wraps `pushState`/`replaceState`, listens for `popstate`/clicks, and enforces route rules and mode allowlists. Redirect targets must be same-origin. A sessionStorage loop breaker stops enforcing after 3 forced navigations in 10s. |
| Network filter | `core/network.ts` | page | Wraps `fetch`/XHR and drops JSON array items matching predicates. Large integers are preserved exactly. A streamed XHR read mid-flight is never filtered. Unverified rules only run with `experimental`. |
| DOM filter | `core/dom.ts` | isolated | Injected CSS (one rule per selector), plus a `MutationObserver` for `hideClosest` and `hideIfText` (one text walk per container). |
| Counter | `core/counter.ts` | isolated | Counts each unique post once it has been ≥50% visible for 1s. Always runs; `postCounter` only controls whether native shows it. |
| Bridge | `core/bridge.ts` | isolated | Sends `ready`, `postViewed`, `routeBlocked`, `ruleHit` (debug), `identity` and `error` to native. **Native treats all of these as untrusted.** |

**Route enforcement in JS is best-effort.** Native observes `webView.url`, which updates on `pushState`, and is the authoritative backstop, with its own loop breaker. Settings changes that affect routes or network filtering reload the web view. CSS/DOM-only changes are pushed live into the isolated world.

## Rule packs (`rules/`)

Rule packs are declarative JSON, validated by `rules/schema/rule-pack.schema.json`. Each pack has a `version` and a `minEngineVersion`. A refreshed pack is used only if it parses, passes validation, has a compatible `minEngineVersion` and a newer `version` than the bundled one. Otherwise the app keeps using the bundled pack.

What a pack **can't** do, and where that is enforced:

| Guarantee | Schema (CI) | Engine | Native |
|---|---|---|---|
| No scripts and no host fields | ✅ (`additionalProperties: false`) | n/a: only known fields are read | ✅ Codable decode ignores unknown fields; the host allowlist is hardcoded |
| Redirect targets and mode homes are same-origin paths | ✅ pattern | ✅ `isSafePath` + URL origin check, `$n` percent-encoded | ✅ `RulePackSelector` (tested) |
| Invalid regexes or selectors can't break the engine | n/a | ✅ dropped and reported | n/a |
| Size caps (pack size, selector count, regex length) | n/a | n/a | ✅ `RulePackSelector` (tested) |

What a pack **can** still do: hide any element or drop any post that matches its selectors or predicates. A compromised repository could therefore censor content inside a platform, but it couldn't exfiltrate data or load other sites. **Refreshed packs must be ed25519-signed before rule refresh ships in a release** (see roadmap).

## Swift layout

- `ios/Packages/RewindCore`: pure Swift with no UIKit or FamilyControls. Settings model, rule-pack decoding and version checks, host allowlist, and the builder for the injected config script. Unit-tested with `swift test`.
- `ios/SocialRewind`: the SwiftUI app. Glue code around WebKit, FamilyControls and ManagedSettings.
- `ios/Extensions/*`: the Screen Time extensions, which share settings through the App Group `group.app.socialrewind`.
