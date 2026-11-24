# Social Rewind for iOS

SwiftUI app, three Screen Time extensions, and `RewindCore`, a pure-Swift package holding the testable logic.

```
ios/
  project.yml                 XcodeGen spec (source of truth; .xcodeproj is generated and gitignored)
  Config/                     Base.xcconfig + your Local.xcconfig (team ID, bundle prefix)
  Packages/RewindCore/        Rule packs, settings, host allowlist, engine config, bridge events, stats
  Shared/                     App Group storage, compiled into the app and every extension
  SocialRewind/               The app: onboarding, home, settings, filtered browser, stats
  Extensions/
    ShieldConfiguration/      Custom shield screen ("Locked by Social Rewind")
    ShieldAction/             Shield buttons; posts the "open in Social Rewind" notification
    DeviceActivityMonitor/    Stub for sleep mode and time limits
```

## Build

Requirements: macOS, Xcode 26 (or the current release), XcodeGen, Node 22+ and pnpm, and an iPhone on iOS 17+. Screen Time shielding doesn't work in the Simulator.

```sh
brew install xcodegen pnpm
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # set DEVELOPMENT_TEAM
cd ios && xcodegen generate && open SocialRewind.xcodeproj
```

Every app build runs `scripts/build-engine-for-ios.sh` first. It builds `engine/` and copies `social-rewind-page.js`, `social-rewind-isolated.js` and `rules/*.json` into `SocialRewind.app/Generated/`. If any of them is missing, **the build fails**: the app must never show a platform without its filters.

Logic tests (no Xcode needed):

```sh
cd ios/Packages/RewindCore && swift test
```

### Family Controls entitlement

All four targets use `com.apple.developer.family-controls`. Development builds on your own device work once the capability is enabled for your team. **TestFlight and App Store builds need Apple to approve the distribution entitlement.** Request it early at developer.apple.com → Account → Family Controls (Distribution), once for each bundle ID: the app and all three extensions.

If `app.socialrewind` isn't registered to your team, set `SR_BUNDLE_PREFIX` in `Local.xcconfig`. The App Group (`group.<prefix>`) follows it automatically, and the code reads it from Info.plist.

## How a session works

1. The user opens Instagram and sees the shield. Tapping **Open in Social Rewind** makes the ShieldAction extension post a notification. Tapping that opens `socialrewind://open/instagram`.
2. `PlatformBrowserView` creates a `WKWebView` with:
   - a persistent, per-platform `WKWebsiteDataStore(forIdentifier:)`;
   - **two** document-start user scripts, each wrapped as `(function(){"use strict";const __SR_CONFIG__ = {...};<bundle>})();` by `EngineConfigBuilder.wrap`, so there's no global for the page to read:
     - `social-rewind-page.js` in the `.page` world (history + fetch/XHR patches);
     - `social-rewind-isolated.js` in `WKContentWorld.world(name: "SocialRewind")` (CSS/DOM filter, counter, bridge);
   - the `socialRewind` message handler, registered **only in the isolated world**.
3. The page stays covered until the engine sends `ready`. If that takes more than 10 seconds or the engine reports an error, the user sees "Filters didn't load / Retry". This fails closed.
4. Bridge messages are untrusted. They're accepted only from the main frame, the isolated world and an allowed https origin. They're validated (`BridgeEvent.validated()`: username regex, length caps), `postViewed` is rate-limited to 5 per second, and the content is used only for counters, stats and the username.
5. Native route backstop: KVO on `webView.url` (which updates on pushState) runs `RouteGuard`, covering mode allowlists, `alwaysAllowRoutes` and "block" rules. A disallowed path loads the mode's home or `/`. More than 3 forced navigations in 10 seconds turns enforcement off for the session and logs it.
6. `HostPolicy` (hardcoded, and never set by rule packs) allows only the platform's own hosts. Only a real link tap (`.linkActivated`) on an off-allowlist host opens the default browser. Every other off-allowlist navigation, and `instagram://` and other app schemes, is cancelled.
7. Settings changes: grayscale and the post counter update live through `window.SocialRewind?.update(...)` in the isolated world. Anything else, including a new or edited username, installs new scripts and **reloads**, so the page-world bundle gets the new closure config.
8. "Saved posts only" needs the account handle (`/{username}/saved/`). Settings show a username field validated with the same regex, and the engine can also report it.
9. Refreshed rule packs must pass `RulePackSelector`: schema, platform, engine version, a higher revision, same-origin paths for `to`, `home` and `startPath`, under 256 KB, at most 500 selectors, and no regex longer than 300 characters.

## Verified vs. unverified

| | Status |
|---|---|
| RewindCore logic | ✅ `swift test`, 38 tests |
| Syntax of all app and extension files | ✅ `swiftc -parse` |
| Type-check of all 15 app and Shared files (Swift 6 mode) | ✅ against the **Mac Catalyst** SDK (UIKit, SwiftUI, WebKit), with stand-in `FamilyControls`/`ManagedSettings` modules. Real Screen Time signatures weren't checked, and Catalyst availability is close to iOS but not identical. A negative control confirmed the check catches errors. |
| The three extensions | ⚠️ parse only: ManagedSettingsUI and DeviceActivity aren't in the Catalyst SDK |
| Shield → notification → deep-link handoff | ❓ roadmap spike 0.4 |
| Async `UNUserNotificationCenterDelegate` methods in `AppDelegate` | ❓ check on the first device build |
| Whether shielding the web domain also blocks our WKWebView | ❓ spike 0.5, so web domains aren't shielded yet |
