# Social Rewind

Use social media without the parts built to keep you scrolling.

Social Rewind locks the social media apps on your phone (using Apple's Screen Time API) and gives you a filtered way back in: the platform's own website, running inside Social Rewind, with the features you chose removed. That means no Reels, no Explore, no suggested posts, no ads, just the parts you actually wanted.

> **Status:** early development. Instagram on iOS is first. Nothing is on the App Store yet.

## How it works

1. **Pick your features.** For each platform, choose what to block, for example Reels, Explore, Stories, comments or ads. Or pick a mode such as *DMs only* or *Saved posts only*.
2. **Lock the app.** Social Rewind uses Apple's Screen Time frameworks (FamilyControls / ManagedSettings) to block the native app.
3. **Browse filtered.** Open the platform inside Social Rewind. A filter engine runs inside the platform's web app and removes what you blocked before you see it.

## Privacy

Social Rewind has **no servers, no accounts, no analytics and no tracking**. Your settings and stats never leave your phone. The app only contacts:

- the social media sites you open in it, and
- *optionally*, this GitHub repository, to download updated filter rules (`rules/*.json`). This is off by default, and the rules are plain data, not code.

See [docs/privacy.md](docs/privacy.md).

## Repository layout

| Path | What's there |
|---|---|
| `engine/` | The filter engine (TypeScript, built into one JS file injected into the web view). Shared by iOS and, later, Android. |
| `rules/` | Declarative filter rules for each platform, plus their JSON schema. Most fixes when a platform changes its site land here. |
| `ios/` | The iOS app and its Screen Time extensions (Swift, SwiftUI, XcodeGen). |
| `android/` | Planned. |
| `docs/` | Architecture, roadmap, decisions and research notes. |

## Building

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full setup. Quick version:

```sh
# Filter engine (any OS)
cd engine && pnpm install && pnpm test && pnpm build

# iOS app (macOS + Xcode required)
brew install xcodegen
cd ios && xcodegen generate && open SocialRewind.xcodeproj
```

## Contributing

Filter rules break whenever a platform changes its site, and fixing them is the most useful contribution. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE). Social Rewind isn't affiliated with or endorsed by any of the platforms it works with. All trademarks belong to their owners.
