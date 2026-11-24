# Social Rewind: notes for agents

An open-source (Apache-2.0) iOS app that blocks social media apps through Apple's Screen Time API and reopens them as filtered web views. Read `docs/architecture.md` before making structural changes.

## Hard constraints
- **No user data collection.** No analytics, crash SDKs, accounts or backend. The only network traffic allowed is (a) the social platform's own hosts and (b) an **opt-in** fetch of `rules/*.json` from this repo's GitHub raw URL.
- **Filter rules are declarative data, never code.** Downloaded rule packs must not be able to run JS or widen the navigation allowlist (App Store Guideline 2.5.2 and our own security model). Host allowlists live in native code only. Redirect targets must be same-origin paths, enforced in the schema, the engine (`isSafePath` + URL origin check) and native.
- **Messages from the web view are untrusted.** Page scripts are the platform's code; native validates every bridge message and only uses it for counters and stats.
- Don't use platform logos or trademarks as Social Rewind branding.
- Never commit captured page fixtures that contain real personal data. `engine/test/fixtures/**/raw/` is gitignored. Scrub fixtures before moving them out of it.

## Layout
- `engine/`: TypeScript filter engine, built by esbuild into **two** bundles injected at document start: `social-rewind-page.js` (page world: history + fetch/XHR patches only, no bridge, no globals) and `social-rewind-isolated.js` (isolated `WKContentWorld` "SocialRewind": CSS/DOM, counter, identity, bridge). Native passes config by closure. Shared with Android later. `pnpm test`, `pnpm build`, `pnpm typecheck`. **Run `scripts/test-all.sh` after any change to `rules/`**, since the Swift tests read the packs too.
- `rules/`: one rule pack per platform (`instagram.json`), validated against `rules/schema/rule-pack.schema.json`.
- `ios/`: XcodeGen spec `project.yml`, app target `SocialRewind`, extensions under `Extensions/`, and pure-Swift logic in the local package `Packages/RewindCore` (testable with `swift test`, no Xcode needed).
- `docs/decisions/`: ADRs. Add one for any significant decision.

## Product decisions (settled)
- Instagram first. Modes: normal, *DMs only*, *Saved posts only* (shows only the user's saved posts).
- Rule refresh is optional and off by default.
- iOS 17 minimum (needs `WKWebsiteDataStore(forIdentifier:)`).
- Development happens on macOS (iOS needs Xcode).

## Status
See `docs/roadmap.md` for which items are done and which are open questions.
