# 0007: Block suggested posts opens Instagram's Following feed

**Status:** accepted (2026-11-27)

## Context
Instagram's main feed is mostly suggested posts and reels. With Block suggested posts and Hide reels on (both default), almost every item was hidden, so the feed trickled in one post at a time (seen on device). Instagram also has a Following feed at `/?variant=following`: only accounts you follow, newest first. It exists on mobile web and scrolls smoothly in Social Rewind (checked on device by switching to it manually).

## Decision
- While **Block suggested posts** is on, Social Rewind opens Instagram on the Following feed, and `/` redirects there unless the query already asks for Following or Favorites.
- Route rules gain two declarative fields (engine 4):
  - `search`: a regex the query must also match.
  - `navigateInApp`: follow the redirect on in-app navigation instead of staying put, so the Home button lands on Following. That's one step back if Following was the previous page, otherwise a load.
- On Following, a tap on a link to `/` is left to the site: Instagram's logo is such a link and opens the Following/Favorites menu, and stopping it broke that menu (seen on device). An in-app address change to `/` reloads Following, because Instagram may already be rendering the main feed by then.
- These redirects aren't reported as blocks, so the "Blocked by your settings" notice doesn't appear.
- Redirect chains resolve in one navigation, for example Reels → `/` → Following.
- Native opens the browser on the Following feed, and blocked pages fall back there.

## Consequences
- The default experience is follows-only and chronological, which is the product's point. The Favorites feed stays reachable.
- Packs with these fields need engine 4 (`minEngineVersion` 4), so older apps refuse them.
- Unverified: how Instagram's Home button navigates (link or `pushState`), and what happens signed out (see the checklist).
