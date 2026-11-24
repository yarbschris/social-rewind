# 0004: Split the engine across two WebKit content worlds

**Status:** accepted (2026-11-24)

## Context
The first engine was one bundle in the page content world, with its config in `window.__SOCIAL_REWIND_CONFIG__` and its API at `window.SocialRewind`. A review found that the platform's own scripts could:
- read the config (settings, username, the whole pack), which makes Social Rewind trivial to fingerprint,
- call `SocialRewind.stop()` or switch modes, and
- post forged events to native through `webkit.messageHandlers`.

## Decision
- **Page world**: only what has to wrap page globals (`history`, `fetch`, `XMLHttpRequest`). No bridge, no globals.
- **Isolated world** (`WKContentWorld` "SocialRewind"): DOM/CSS filtering, the counter, identity, and the bridge, with the message handler registered only in this world.
- **Config by closure** for both bundles, never as a global.
- **Shared DOM as the only channel** from page to isolated (`html[data-sr-path]`, `html[data-sr-event]`), treated as untrusted.
- **Native URL observation** is the authoritative route enforcement. JS routing is best-effort.
- Route- and network-affecting settings changes **reload** the web view instead of being pushed live.

## Consequences
- A hostile page can still disable its own page-world filtering (router, network). The isolated DOM filter and the native URL backstop remain.
- Bridge messages are untrusted regardless: native validates usernames, rate-limits counters, and acts on nothing else.
- Android needs an equivalent split. `WebView` has no content worlds, so its approach is still to be decided.
