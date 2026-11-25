# Contributing

## Setup

### Required tools

| Tool | Why | Install |
|---|---|---|
| macOS 15+ | iOS builds need Xcode | — |
| Xcode 26 (or the latest release) | Builds the iOS app and extensions | Mac App Store, then `sudo xcode-select -s /Applications/Xcode.app` |
| XcodeGen | Generates `SocialRewind.xcodeproj` from `ios/project.yml` | `brew install xcodegen` |
| Node 22+ and pnpm | Filter engine | `brew install node pnpm` |
| A physical iPhone (iOS 17+) | Screen Time shielding doesn't work in the Simulator | — |
| Apple Developer Program | Family Controls capability, device builds, TestFlight | developer.apple.com |

Engine-only contributors just need Node and pnpm, on any OS.

### Engine

```sh
cd engine
pnpm install
pnpm test        # unit tests (vitest + happy-dom)
pnpm typecheck
pnpm build       # → engine/dist/social-rewind-{page,isolated}.js
```

### iOS

```sh
cd ios
xcodegen generate
open SocialRewind.xcodeproj
```

A pre-build step builds the engine and copies the bundle and `rules/*.json` into the app's resources.

The Family Controls entitlement for *distribution* requires an approval request to Apple. Development builds can use the capability without it.

## Fixing broken filter rules

Most breakages come from a platform renaming its markup. Usually the fix is:

1. Reproduce it in the app with **Settings → Developer → Show filter debug overlay** turned on.
2. Update the selector, text match or JSON predicate in `rules/<platform>.json`.
3. Add or update a scrubbed fixture in `engine/test/fixtures/<platform>/` and a test that covers it.
4. Bump the rule pack's `revision`.

Prefer stable hooks, in this order: URL/`href` patterns → ARIA roles and labels → visible text → structure. Never use generated class names.

## Fixtures and privacy

Captured HTML or JSON from your own account can contain names, messages and photos. Save raw captures to `engine/test/fixtures/<platform>/raw/` (gitignored), and commit only scrubbed or synthetic versions.

## Commits

Work on a feature branch, never directly on `main`, and open a pull request. Use one branch per feature or fix, named by area: `rules/…`, `engine/…`, `ios/…`, `docs/…`. That keeps each change easy to review, track and roll back. `main` is protected: a PR can merge only when the **engine OK** and **iOS OK** checks pass. They run on every PR and skip the expensive jobs when the PR doesn't touch what they test, so docs-only PRs pass in seconds.

Small, focused commits. Run `scripts/test-all.sh` (engine, rule validation and RewindCore) before opening a PR. Rule packs are read by both the engine and the Swift code, so a rules change must pass both.
