# 0006: Keep each platform's web view alive between opens

**Status:** accepted (2026-11-26)

## Context
Every open of the filtered browser created a new `WKWebView`, and every close destroyed it. So each open loaded the platform from scratch: its JavaScript started again, the feed was fetched again and the scroll position was lost. The native app stays warm in the background, which made the filtered view feel much slower than the app.

## Decision
- **One kept `BrowserSession` per platform**, owned by `AppModel.browserSessions`. It holds the `WKWebView`, its delegate and the `BrowserController`. `PlatformBrowserView` only hosts the web view, so closing the browser takes the web view out of the view hierarchy without tearing it down.
- **Reopening shows the page where the user left it.** The session counter and reminders still start over on each open (`BrowserController.beginVisit`).
- **Settings changed while the browser was closed reload it on the next open.** Settings, the username and the rules are all in the injected config, so the open compares it with what the web view runs. Any difference installs the new scripts and reloads behind the filter cover, as a change made while the browser is open does. This stays fail-closed: a kept page never runs older filters than the user chose.
- **Nothing plays while hidden:** closing suspends all media playback, and opening lifts the suspension.
- **Memory:** on a memory warning, sessions that aren't showing are discarded, and the next open starts a fresh page. If iOS kills the web content process, the existing handler reloads the page behind the cover.

## Consequences
- Reopening is near-instant once the page has loaded once in this app launch.
- The page's own engine remembers posts it already counted, so a post seen in an earlier visit to the same kept page doesn't count again in a later visit.
- The page keeps a little memory in the web content process while the browser is closed. iOS throttles the timers of a hidden page.
- Not covered here: a feed left open for hours comes back as it was. If that turns out to feel stale, a later change can reload after a long gap.
