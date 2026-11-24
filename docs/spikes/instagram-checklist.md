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
