# 0002: Optional, declarative rule refresh

**Status:** accepted (2026-11-24)

## Context
Platforms change their markup often. If fixes could only ship with app updates, every breakage would leave filters broken for 1–3 days while App Store review runs. The app must also make no network requests except to the platforms themselves.

## Decision
- Rule packs are bundled with the app and always work offline.
- Users can turn on **"Update filter rules automatically"** (off by default). The app then fetches `https://raw.githubusercontent.com/<org>/social-rewind/main/rules/<platform>.json` and sends nothing beyond a plain GET.
- A pack is data only: selectors, text matches, JSON predicates and route patterns. It can't run code, add hosts or change native behavior. This keeps rule refresh within App Store Guideline 2.5.2.
- A fetched pack is adopted only if it validates, `minEngineVersion <= engineVersion`, and its `version` is newer than the one currently in use.

## Consequences
- GitHub sees the user's IP address when refresh is on. This is disclosed in `docs/privacy.md`.
- Compromising the repository would let an attacker hide or redirect content within a platform, but not exfiltrate data. Planned mitigation: ed25519 signatures checked against a public key compiled into the app.
