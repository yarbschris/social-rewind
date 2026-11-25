# Instagram on-device spike checklist

## Confirmed so far (Safari lab, iOS Simulator Safari, 2026-11-24)
- ✅ **Injected `<style>` is not blocked by Instagram's CSP.** The lab reported "style sheet applied: yes".
- ✅ **Filtered taps reloaded the page** when they redirected (comments, search). Fixed: in-app navigation to filtered pages is now inert.
- ✅ **The search tab goes to `/explore/`.** Kept reachable for account search, with post tiles hidden.
- ✅ **Swiping on from a reel shared in DMs shows further reels, each one matched by `blockReels`.** Decision: a shared reel may open, but you can't scroll on to more (`hideAllButFirst` on reel routes). Still to verify: the path when a shared reel opens, and the reel container markup.
- ✅ **"Suggested for you" always sat inside an `article`** (3 of 3 on Home), and `hideSuggested.dom0` caught each one. The separate carousel rule matched nothing, so it was removed.
- ✅ Post counter counts on Home (7 posts). `a[href="/"]`, `/explore/`, `/reels/` and `/direct/inbox/` each appear once (the nav bar).
- ✅ **Ads:** `blockAds.dom0` catches real ads (user confirmed).
- ✅ **Feed reels:** caught by `blockReels.dom0`.
- ✅ **Identity:** rev 5 nav-scoped detection works.
- ✅ **Nav icons and action buttons** are `svg[role="img"][aria-label="…"]` → `span` → `div` → `div[role="button"]` (Home, Explore, Reels, Messages, Like…).
- ✅ The XHR "access control checks" errors are Instagram's own, logged during reload before our snippet runs.
- ✅ **Comment buttons (rev 7, confirmed hidden; Like and Share stay):** rev 6's nesting guess matched nothing; only the bare `svg[aria-label="Comment"]` matched (9 in the reel viewer), and an svg can't show a debug label. Rev 7 walks up from the icon to the nearest `[role="button"]` (`hideComments.dom0`). Needs re-checking: the labelled box should be icon-sized.
- ✅ **Shared reel viewer (from DMs):** opens as an overlay; the URL stays on the thread and nothing is pushed (no `routeBlocked`). No `article`s. Each reel is a `div[role="group"]` containing its `video` and two `/reels/audio/<id>/` links. The opened reel and a 9-slot list of more reels are siblings under one wrapper. Rev 8 (`blockReels.dom2`, engine 2 `branch`) hides that whole list on `/direct/` paths. Confirmed in hide mode: the opened reel plays and swiping goes nowhere.
- ✅ **Stories tray (rev 7, 1 match on Home):** no `/stories/` links. Bubbles are `div[role="button"][aria-label^="Story by"]`, all direct children of one tray `div` under `main`. Rev 7 hides a div with a story button as its 2nd child (so a single story ring on a post avatar is skipped). English-only label; needs a locale-free signal before localization. Should match exactly 1 on Home.
- ❌ **Identity:** not detected with `[role=navigation]`. Rev 5 searches inside the nav bar (the common ancestor of the Home and Inbox links). Needs re-checking.

Run on a physical iPhone with a development build. Turn on **Settings → Developer → Filter debug overlay** so hidden elements are outlined instead of removed.

## 0.2 Web view basics
- [ ] Log in at instagram.com inside the app. Kill the app, relaunch: still logged in?
- [ ] 2FA / "suspicious login" challenge flow completes.
- [ ] Home feed, profile, a post, saved posts (`/<you>/saved/`), DMs inbox and a thread all load.
- [ ] Do any "Open in app" banners or universal links try to launch the native app?

## 0.3 Network layer
With **Developer → Experimental network filtering** on, connect Safari Web Inspector (Mac Safari → Develop → your iPhone → Social Rewind):
- [ ] Network tab: which requests carry feed items? (URL path, method, content-type, streamed or not)
- [ ] Is the first feed page server-rendered in the HTML instead of fetched?
- [ ] Save 1–2 responses to `engine/test/fixtures/instagram/raw/` (gitignored). Note where ads, suggested posts and reels sit in the JSON (key names only) in `instagram-network.md`.

## 0.6 Feature presence on mobile web
For each one, note the selector/label you'd use, or "not present on mobile web":
- [ ] Reels tab and reels in the feed
- [ ] Explore grid and search results
- [ ] Stories tray and story viewer
- [ ] Comments link and composer
- [ ] "Sponsored" label
- [ ] "Suggested for you" posts and the suggested-accounts carousel
- [ ] Reposts label
- [ ] "AI info" label
- [ ] Story ads
- [ ] Navigation bar profile link (used to detect the username for Saved-only mode)

## Requested next
- ⬜ **Suggested accounts** (rev 9, `hideSuggestedAccounts`, its own toggle): the block's "See all" link goes to `/explore/people/` (now redirected home). Rule: the grandparent of that link (header row plus card carousel). The 20 "Suggested for you" text nodes found were all in feed reels, already hidden. Check that `hideSuggestedAccounts.css0` is exactly 1 per block and the whole carousel goes.
- ⬜ **Notes tray in DMs** (rev 9, `hideNotes`, off by default): a `ul` of `li > div[role="button"]` bubbles; the user's own is labelled "Your note". Rule: hide the `ul` containing that text on `/direct/` paths. English-only, and it won't fire if the user's own bubble is missing.

## Open questions from the engine review (verify, don't assume)
Each of these came from a reviewer's memory of Instagram, so it's as unverified as the original rules.
- [x] **Swallowed `pushState`:** opening a reel from a DM pushes nothing, so this case doesn't arise there. Still worth watching on other buttons.
- [ ] **Hide feed and runaway pagination:** with `hideFeed` on, does the Network tab show feed pages loading endlessly? If so, hide the feed container (sentinel included), or block the feed request natively.
- [x] **Stories tray markup:** buttons, not links (see above).
- [ ] **Suggested-accounts carousel:** does the `main div:has(> div > a[href^="/explore/people/"])` rule hide the whole carousel or only its header?
- [ ] **"Ad" false positives:** do comment previews or captions ever render "Ad" or "Sponsored" as a standalone text node inside an `article`? If so, scope the rule with `within: "header"`, using whatever the real header element is.
- [ ] **Posts after "You're all caught up":** do they carry a per-post "Suggested" label at all?
- [ ] **"reposted" label:** is it a standalone text node?
- [ ] **Identity detection:** does the profile-picture alt text vary by locale? Is there a locale-free signal?
- [ ] **`/explore/search/`:** is it a real standalone route on mobile web?
- [ ] **`product_type: "clips"`:** is it only on Reels, or also on saved and profile videos?
- [ ] **Grayscale:** does `filter: grayscale(1)` on `<html>` hurt scrolling, video, or fixed-position elements in WebKit? If so, do grayscale natively.
