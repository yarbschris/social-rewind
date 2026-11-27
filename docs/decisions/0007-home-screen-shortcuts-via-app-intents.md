# 0007: Home Screen shortcuts through App Intents

**Status:** accepted (2026-11-27)

## Context
Users want an icon on the Home Screen that opens a platform straight into Social Rewind, ideally in the spot where the locked native app used to be. The app already handles `socialrewind://open/<platform>`. iOS gives an app no way to add a Home Screen icon by itself.

Options considered:
- **App Intent + App Shortcut.** It runs inside the app target, needs no new extension or entitlement, and works on iOS 17. Users add it to the Home Screen through the Shortcuts app, and it also works from Siri, Spotlight, the Action button and Back Tap.
- **A WidgetKit widget with `widgetURL`.** This needs a new extension target, and the smallest Home Screen widget on iPhone takes the space of 2×2 icons.
- **Web clips installed through a `.mobileconfig` profile.** These are clunky, and asking users to install a configuration profile works against the app's trust model.
- **Alternate app icons.** These only change Social Rewind's own icon, one at a time.

## Decision
- `OpenPlatformIntent` (`ios/SocialRewind/App/AppShortcuts.swift`) takes a `ShortcutPlatform` and opens the app (`openAppWhenRun`). It goes through the same deep link as the shield's notification, so the same checks apply: the platform must be available and onboarding finished.
- `SocialRewindShortcuts` registers it as an App Shortcut, so "Open Instagram in Social Rewind" appears in Shortcuts, Spotlight and Siri without any setup.
- `ShortcutPlatform` lists available platforms by hand, because App Intents reads enum cases at build time. **Add a case when a platform becomes available.**
- `DeepLinkRouter` is the single entry for links from outside SwiftUI (notifications and intents). It holds a link that arrives on a cold launch until the model exists.
- Each platform's settings explain how to add the shortcut to the Home Screen and open a new shortcut in the Shortcuts app (`shortcuts://create-shortcut`).

## Consequences
- Social Rewind ships no platform artwork. Users pick their own name and icon in Shortcuts.
- `openAppWhenRun` is deprecated from iOS 26 in favour of `supportedModes`. Switch when the minimum reaches iOS 26.
- The same intent lets a user set up a Shortcuts personal automation ("When Instagram is opened, run Open Instagram in Social Rewind"). That could skip the shield's notification step. It's untested, and it's the user's own setup, not something the app can turn on.
- Not yet checked on a device or in the Simulator: the steps in the settings text, and whether a Home Screen shortcut opens the app directly or shows a Shortcuts banner first.
- A widget can be added later on top of this, using the same deep link.
