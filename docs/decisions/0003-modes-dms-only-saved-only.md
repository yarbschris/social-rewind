# 0003: Modes (DMs only, Saved posts only)

**Status:** accepted (2026-11-24)

## Decision
On top of individual feature toggles, each platform can have an exclusive **mode**:

- **Normal:** feature toggles apply.
- **DMs only:** only messaging routes are reachable. Home redirects to the inbox.
- **Saved posts only:** only the user's saved-posts collection and the posts opened from it are reachable. Home redirects to saved.

A mode is a route allowlist plus a home route, defined in the rule pack (`modes`). Feature toggles still apply inside a mode (for example, hide comments while in Saved only).
