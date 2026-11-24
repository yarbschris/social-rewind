# Filter engine

TypeScript, bundled into a single IIFE (`dist/social-rewind-engine.js`) that the native shell injects at **document start** in the page's content world. It never makes network requests of its own.

```sh
pnpm install
pnpm test            # vitest + happy-dom
pnpm typecheck
pnpm validate-rules  # rules/*.json against the schema
pnpm build           # add -- --minify for release
```

## Contract with native

Native defines the config **before** the bundle runs:

```js
window.__SOCIAL_REWIND_CONFIG__ = { platform, settings, rules, username?, debug?, experimental? };
```

…and can then call `window.SocialRewind.update(settings)` and `window.SocialRewind.setUsername(name)`.

Events go to `webkit.messageHandlers.socialRewind` (iOS) or `SocialRewindAndroid.postMessage(json)` (Android): `ready`, `postViewed`, `routeBlocked`, `ruleHit` (debug only), `identity`, `error`. See `src/core/types.ts`, which is the source of truth.

## Modules

| File | Role |
|---|---|
| `core/compile.ts` | Settings + rule pack → active rules (ids, regexes; unverified network rules gated behind `experimental`) |
| `core/router.ts` | Route decisions; wraps `history`, `popstate` and link clicks; hard-redirect fallback |
| `core/network.ts` | Wraps `fetch`/XHR and filters JSON bodies (`core/json-filter.ts`) |
| `core/dom.ts` | Injected CSS (one rule per selector), `MutationObserver` rules, grayscale, `html[data-sr-path]` |
| `core/counter.ts` | Unique posts seen ≥50% for ≥1s |
| `core/engine.ts` | Wiring, isolating each layer's failures, identity (username) resolution |
