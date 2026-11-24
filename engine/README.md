# Filter engine

TypeScript, built into two IIFE bundles that the native shell injects at **document start**. The engine never makes network requests of its own.

| Bundle | Content world | Contains |
|---|---|---|
| `dist/social-rewind-page.js` | page (shares the site's JS globals) | history and fetch/XHR patches only. No bridge, no globals. |
| `dist/social-rewind-isolated.js` | `WKContentWorld` "SocialRewind" | CSS/DOM filter, counter, identity, bridge to native |

Why the split: anything in the page world can be read and tampered with by the platform's own scripts. Only the parts that *must* wrap page globals live there. The worst a hostile page can do to them is turn off its own filtering. The worlds share only the DOM: the page bundle writes `html[data-sr-path]` and `html[data-sr-event]`, and the isolated bundle treats both as untrusted.

```sh
pnpm install
pnpm test            # vitest + happy-dom
pnpm typecheck
pnpm validate-rules  # rules/*.json against the schema
pnpm build           # add -- --minify for release
```

## Contract with native

Native wraps **each** bundle so the config is a closure variable, never a global:

```js
(function(){ "use strict"; const __SR_CONFIG__ = { platform, settings, rules, username?, debug?, experimental? }; /* bundle */ })();
```

- **Live updates** (CSS/DOM only): `SocialRewind.update(settings)`, evaluated *in the isolated world*. Changes to mode, routes or network settings, or a newly learned username, need a web view reload so the page bundle gets a new config.
- **Events** go to `webkit.messageHandlers.socialRewind`, registered in the isolated world only, or `SocialRewindAndroid.postMessage(json)` on Android. Types: `ready`, `postViewed`, `routeBlocked`, `ruleHit` (debug only), `identity`, `error`. Native must treat them as untrusted. See `src/core/types.ts`, which is the source of truth.
- **Route enforcement in JS is best-effort.** The native shell observes `webView.url` as the authoritative backstop.

## Modules

| File | Role |
|---|---|
| `core/compile.ts` | Settings + rule pack → active rules (ids, regexes; unverified network rules gated behind `experimental`) |
| `core/router.ts` | Route decisions; wraps `history`, `popstate` and link clicks; same-origin target check; sessionStorage loop breaker |
| `core/network.ts` | Wraps `fetch`/XHR and filters JSON bodies (`core/json-filter.ts`, which keeps integers above 2^53 exact). An XHR the page reads mid-stream is never filtered. |
| `core/dom.ts` | Injected CSS (one rule per selector), `MutationObserver` rules, grayscale, `html[data-sr-path]` |
| `core/counter.ts` | Unique posts seen ≥50% for ≥1s |
| `core/engine.ts` | `startPage` / `startIsolated` wiring, failure isolation, page→isolated event relay, identity |
| `src/page.ts`, `src/isolated.ts` | Bundle entry points |
