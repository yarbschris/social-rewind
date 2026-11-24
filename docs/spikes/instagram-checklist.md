# Instagram on-device spike checklist

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

## Open questions from the engine review (verify, don't assume)
Each of these came from a reviewer's memory of Instagram, so it's as unverified as the original rules.
- [ ] **Swallowed `pushState`:** when a blocked route is pushed (for example, a reel opened from a DM via a button), does Instagram render the blocked view anyway? If so, check that the native URL observer catches it.
- [ ] **Hide feed and runaway pagination:** with `hideFeed` on, does the Network tab show feed pages loading endlessly? If so, hide the feed container (sentinel included), or block the feed request natively.
- [ ] **Stories tray markup:** are tray items `a[href^="/stories/"]` links or buttons? Does `ul:has(> li a[href^="/stories/"])` match the tray?
- [ ] **Suggested-accounts carousel:** does the `main div:has(> div > a[href^="/explore/people/"])` rule hide the whole carousel or only its header?
- [ ] **"Ad" false positives:** do comment previews or captions ever render "Ad" or "Sponsored" as a standalone text node inside an `article`? If so, scope the rule with `within: "header"`, using whatever the real header element is.
- [ ] **Posts after "You're all caught up":** do they carry a per-post "Suggested" label at all?
- [ ] **"reposted" label:** is it a standalone text node?
- [ ] **Identity detection:** does the profile-picture alt text vary by locale? Is there a locale-free signal?
- [ ] **`/explore/search/`:** is it a real standalone route on mobile web?
- [ ] **`product_type: "clips"`:** is it only on Reels, or also on saved and profile videos?
- [ ] **Grayscale:** does `filter: grayscale(1)` on `<html>` hurt scrolling, video, or fixed-position elements in WebKit? If so, do grayscale natively.
